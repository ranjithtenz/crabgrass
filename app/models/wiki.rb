#  This is a generic versioned wiki, primarily used by the WikiPage,
#  but also used directly sometimes by other classes (like for Group's
#  landing page wiki's).
#
#     create_table "wiki_versions", :force => true do |t|
#       t.integer  "wiki_id",    :limit => 11
#       t.integer  "version",    :limit => 11
#       t.text     "body"
#       t.text     "body_html"
#       t.datetime "updated_at"
#       t.integer  "user_id",    :limit => 11
#     end
#
#     add_index "wiki_versions", ["wiki_id"], :name => "index_wiki_versions"
#     add_index "wiki_versions", ["wiki_id", "updated_at"], :name => "index_wiki_versions_with_updated_at"
#
#     create_table "wikis", :force => true do |t|
#       t.text     "body"
#       t.text     "body_html"
#       t.datetime "updated_at"
#       t.integer  "user_id",      :limit => 11
#       t.integer  "version",      :limit => 11
#       t.integer  "lock_version", :limit => 11, :default => 0
#       t.text     "edit_locks"
#     end
#
#     add_index "wikis", ["user_id"], :name => "index_wikis_user_id"
#

##

# requirements/ideas:
# 1. nothing should get saved until we say save!
# 2. updating body automatically updates html and structure
# 3. wiki should never get saved with body/body products mismatch
# 4. loaded wiki should see only the latest body products, if body was updated from outside
class Wiki < ActiveRecord::Base
  include WikiExtension::Locking
  include WikiExtension::Sections

  # a wiki can be used in multiple places: pages or profiles
  has_many :pages, :as => :data
  has_one :profile

  has_one :section_locks, :class_name => "WikiLock", :dependent => :destroy

  serialize :raw_structure, Hash

  # need more control than composed of
  attr_reader :structure

  before_save :update_body_html_and_structure
  before_save :update_latest_version_record

  # section locks should never be nil
  alias_method :existing_section_locks, :section_locks
  def section_locks(force_reload = false)
    # current section_locks or create a new one if it doesn't exist
    # will save the wiki (if wiki is a new_record?) and will create a new WikiLock
    existing_section_locks(force_reload) || build_section_locks(:wiki => self)
  end

  acts_as_versioned :if => :create_new_version? do
    def self.included(base)
      base.belongs_to :user
    end
  end

  # only save a new version if the body has changed
  def create_new_version? #:nodoc:
    body_updated = body_changed?
    recently_edited_by_same_user = !user_id_changed? and (updated_at and (updated_at > 30.minutes.ago))

    return versions.empty? || (body_updated && !recently_edited_by_same_user)
  end

  # returns first version since +time+
  def first_version_since(time)
    return nil unless time
    versions.first :conditions => ["updated_at <= :time", {:time => time}],
      :order => "updated_at DESC"
  end

  # reverts and keeps all the old versions
  def revert_to_version(version_number, user)
    version = versions.find_by_version(version_number)
    self.body = version.body
    self.user = user
    save!
    smart_save!(:body => version.body, :user => user)
  end

  # reverts and deletes all versions after the reverted version.
  def revert_to_version!(version_number, user=nil)
    revert_to(version_number)
    destroy_versions_after(version_number)
  end

  def update_document!(user, current_version, text)
    update_section!(:document, user, current_version, text)
  end

  def update_section!(section, user, current_version, text)
    if self.version > current_version
      raise ErrorMessage.new("can't save your data, someone else has saved new changes first.")
    end

    if sections_locked_for(user).include? section
      raise ErrorMessage.new("Can't save '#{section}' since someone has locked it.")
    end

    set_body_from_section(section, text)
    unlock!(section, user)

    self.user = user
    self.save!
  end

  # updating body will invalidate body_html
  # reading body_html or saving this wiki
  # will regenerate body_html from body if render_body_html_proc is available
  def body=(body)
    write_attribute(:body, body)
    # invalidate body_html and raw_structure
    if body_changed?
      write_attribute(:body_html, nil)
      write_attribute(:raw_structure, nil)
    end
  end

  # will render if not up to date
  def body_html
    update_body_html_and_structure

    read_attribute(:body_html)
  end

  # will calculate structure if not up to date
  # calculating structure will also update body_html
  def raw_structure
    update_body_html_and_structure

    read_attribute(:raw_structure) || write_attribute(:raw_structure, {})
  end

  def structure
    @structure ||= WikiExtension::WikiStructure.new(raw_structure, body.to_s)
  end

  # sets the block used for rendering the body to html
  def render_body_html_proc &block
    @render_body_html_proc = block
  end

  # renders body_html and calculates structure if needed
  def update_body_html_and_structure
    return unless needs_rendering?
    write_attribute(:body_html, render_body_html)
    write_attribute(:raw_structure, render_raw_structure)
  end

  # returns true if wiki body is fresher than body_html
  def needs_rendering?
    html = read_attribute(:body_html)
    rs = read_attribute(:raw_structure)

    # whenever we set body, we reset body_html to nil, so this condition will
    # be true whenever body is changed
    # it will also be true when body_html is invalidated externally (like with Wiki.clear_all_html)
    (html.blank? != body.blank?) or rs.blank?
  end

  # update the latest Wiki::Version object with the newest attributes
  # when wiki changes, but a new version is not being created
  def update_latest_version_record
    # only need to update the latest version when not creating a new one
    return if create_new_version?
    versions.find_by_version(self.version).update_attributes(
              :body => body,
              # read_attributes for body_html and raw_structure
              # because we don't want to trigger another rendering
              # by calling our own body_html method
              :body_html => read_attribute(:body_html),
              :raw_structure => read_attribute(:raw_structure),
              :user => user,
              :updated_at => Time.now)
  end

  ##
  ## RELATIONSHIP TO GROUPS
  ##

  # clears the rendered html. this is called
  # when a group's name is changed or some other event happens
  # which might affect how the html is rendered by greencloth.
  # this only clears the primary group's wikis, which should be fine
  # because link_context just uses the primary group's name.
  def self.clear_all_html(group)
    # for wiki's owned by pages
    Wiki.connection.execute("UPDATE wikis set body_html = NULL WHERE id IN (SELECT data_id FROM pages WHERE data_type='Wiki' and group_id = #{group.id.to_i})")
    # for wiki's owned by groups
    Wiki.connection.execute("UPDATE wikis set body_html = NULL WHERE id IN (SELECT wiki_id FROM profiles WHERE entity_id = #{group.id.to_i})")

  end

  ##
  ## RELATIONSHIP TO PAGES
  ##

  # returns the page associated with this wiki, if any.
  def page
    # we do this so that we can access the page even before page or wiki are saved
    return pages.first if pages.any?
    return @page
  end
  def page=(p) #:nodoc:
    @page = p
  end

  ##
  ## PROTECTED METHODS
  ##

  protected

  # # used when wiki is rendered for deciding the prefix for some link urls
  def link_context
    if page and page.owner_name
      #.sub(/\+.*$/,'') # remove everything after +
      page.owner_name
    elsif profile
      profile.entity.name
    else
      'page'
    end
  end

  def destroy_versions_after(version_number)
    versions.find(:all, :conditions => ["version > ?", version_number]).each do |version|
      version.destroy
    end
  end

  # returns html for wiki body
  # user render_body_html_proc if available
  # or default GreenCloth rendering otherwise
  def render_body_html
    if @render_body_html_proc
      @render_body_html_proc.call(body.to_s)
    else
      GreenCloth.new(body.to_s, link_context, [:outline]).to_html
    end
  end

  def render_raw_structure
    GreenCloth.new(body.to_s).to_structure
  end

  private


end
