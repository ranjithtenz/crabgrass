=begin

ParticipationController
---------------------------------

This is a controller for managing participations with a page
(ie user_participations and group_participations).

=end

class BasePage::ParticipationController < ApplicationController

  before_filter :login_required, :except => [:auto_complete_for_recipient_name, :new_recipient]

  verify :method => :post, :only => [:move]

  helper 'base_page', 'base_page/participation'
  
  include BasePageHelper

  #auto_complete_for :recipient, :name
  
  protect_from_forgery :except => [:auto_complete_for_recipient_name, :new_recipient]
  #       if @share_groups.nil?
  #       @share_page_groups    = @page ? @page.namespace_groups : []
  #       @share_contributors   = @page ? @page.contributors : []
  #       all_groups = current_user.all_groups.sort_by {|g|g.name}
  #       @share_groups      = current_user.all_groups.select {|g|g.normal?}
  #       @share_networks    = current_user.all_groups.select {|g|g.network?}
  #       @share_committees  = current_user.all_groups.select {|g|g.committee?}
  #       @share_friends        = current_user.contacts.sort_by{|u|u.name}
  #       @share_peers          = current_user.peers.sort_by{|u|u.name}

  #       params[:recipients] ||= {}

  def auto_complete_for_recipient_name
    # setup_sharing_populations
    # @recipients = [@share_page_groups, @share_contributors, @share_groups,
    #               @share_networks, @share_committees, @share_friends,
    #               @share_peers].flatten.compact.uniq

     # getting all friends or peers of the user
    @users = User.find(:all, :conditions => "login LIKE '%#{recipient_name}%' AND id IN (#{[current_user.contact_ids, current_user.peer_ids].flatten.uniq!.join(', ')})")
    @groups = Group.find(:all, :conditions => "name LIKE '%#{recipient_name}%' AND id IN (#{current_user.group_ids.join(', ')})")
   
    @all_users = User.find(:all)
    @all_users.select {|user| user.profiles.public.may_pester? }
    
   # @all_users = User.find(:all, :joins => :profiles, :group => "profiles.stranger HAVING profiles.stranger = true")
        
    @recipients = (@users + @groups + @all_users).uniq!
 
    @recipients = @recipients.select { |rcpt|
      (rcpt.name =~ Regexp.new(params[:recipient][:name]) ||
       rcpt.display_name =~ Regexp.new(params[:recipient][:name]))
    }
    
    render :partial => 'base_page/auto_complete/recipient'
  end
  
  
  # TODO: add non-ajax version
  # TODO: send a 'made public' message to watchers
  # Requires :admin access
  def update_public
    @page.public = ('true' == params[:public])
    @page.updated_by = current_user
    @page.save
    render :template => 'base_page/participation/reset_public_line'
  end

  # post
  def add_star
    @page.add(current_user, :star => true).save!
    redirect_to page_url(@page)
  end
  def remove_star
    @page.add(current_user, :star => false).save!
    redirect_to page_url(@page)
  end

  # xhr
  def add_watch
    @upart = @page.add(current_user, :watch => true)
    @upart.save!
    render :template => 'base_page/participation/reset_watch_line'
  end
  
  def remove_watch
    @upart = @page.add(current_user, :watch => false)
    @upart.save!
    render :template => 'base_page/participation/reset_watch_line'
  end

  def show_popup
    render :template => 'base_page/participation/show_' + params[:name] + '_popup'
  end

  # moves this page to a new group.
  # requires :admin access.
  def move
    if params[:cancel]
      redirect_to page_url(@page)
    elsif params[:group_id].any?
      group = Group.find params[:group_id]
      raise PermissionDenied.new unless current_user.member_of?(group)
      @page.remove(@page.group) if @page.group
      @page.owner = group
      current_user.updated(@page)
      @page.save!
      clear_referer(@page)
      redirect_to page_url(@page)      
    end
  end

  # this is very similar to move.
  # only allow changing the owner to someone who is already an admin
  def set_owner
    owner = (User.find_by_login(params[:owner]) || Group.find_by_name(params[:owner]))
    raise PermissionDenied.new unless owner.may?(:admin,@page)
    @page.owner = owner
    @page.save!
    clear_referer(@page)
    redirect_to page_url(@page)
  end
  
  ##
  ## PAGE SHARING
  ## 

  # share this page with a notice message to any number of recipients. 
  #
  # if the recipient is a user name, then the message and the page show up in
  # user's inbox, and optionally they are alerted via email.
  #
  # if the recipient is an email address, an email is sent to the address with a
  # magic url that lets the recipient view the page by clicking on a link
  # and using their email as the password.
  # 
  # the sending user must have admin access to send to recipients
  # who do not already have the ability to view the page.
  # 
  # the recipient may be an entire group, in which case we grant access
  # to the group and send emails to each user in the group.
  #
  # you cannot share to users/groups that you cannot pester, unless
  # the page is private and they already have access.
  #
  
  
#  "recipient"=>{"name"=>"", "access"=>"admin"}, "recipients"=>{"aaron"=>{"access"=>"admin"}, "the-true-levellers"=>{"access"=>"admin"}}

  def share
    #debugger
    if params[:cancel] || !params[:recipients]
      close_popup
    elsif params[:recipient] and params[:recipient][:name].any?
      # add one recipient to the list
      recipient_name = params[:recipient][:name].strip 
      @recipient = User.find_by_login(recipient_name) || Group.find_by_name(recipient_name)
      if @recipient.nil?
        flash_message :error => 'no such name'
      elsif !@recipient.may_be_pestered_by?(current_user)
        flash_message :error => 'you may not pester'
      end
      render :partial => 'base_page/participation/add_recipient'
    else
      # recipients with options, that looks like
      # {:animals => [:grant_access => :view], :blue => [:grant_access => :admin]
      recipients_with_options = get_recipients_with_options(params[:recipients])

      options = {
        :message => params[:notification][:message_text],
        :send_emails => params[:notification][:send_emails],
        :send_via_email => params[:notification][:send_via_email],
        :send_via_textmessage => params[:notification][:send_via_textmessage],
        :send_via_chat => params[:notification][:send_via_chat],
        :send_only_with_encryption => params[:notification][:send_only_with_encryption],
        :send_to_inbox => params[:notification][:send_to_inbox],
        :mailer_options => mailer_options
      }
      # current_user.share_page_with!(@page, recipients, options)
      current_user.share_page_by_options!(@page, recipients_with_options, options)      
      @page.save!
      flash_message :success => "You successfully shared this page."[:shared_page_success]
      close_popup
    end
  end

  # handles the notification with or without sharing
  def notify
    share 
    return
  end
  
  ##
  ## PAGE DETAILS
  ## participation and access
  ##

  def close_details
    close_popup
  end

  # create or update a user_participation object, granting new access. 
  def create
    begin
      users, groups, emails = Page.parse_recipients!(params[:add_names])
      (users+groups).each do |thing|
        @page.add(thing, :access => params[:access].to_sym).save!
      end
      @page.save!
      render :update do |page|
        page.replace_html 'permissions_tab', :partial => 'base_page/participation/permissions'
      end
    rescue Exception => exc
      flash_message_now :exception => exc
      show_error_message
    end
  end

  ## technically, we should probably not destroy the participations
  ## however, since currently the existance of a participation means
  ## view access, then we need to destory them to remove access. 
  def destroy
    upart = (UserParticipation.find(params[:upart_id]) if params[:upart_id])
    if upart and upart.user_id != @page.created_by_id
      @page.remove(upart.user) # this is the only way users should be removed.
      @page.save!
    end

    gpart = (GroupParticipation.find(params[:gpart_id]) if params[:gpart_id])
    if gpart and gpart.group_id != @page.group_id
      @page.remove(gpart.group) # this is the only way groups should be removed.
      @page.save!
    end

    render :update do |page|
      page.hide dom_id(upart || gpart)
    end
  end

  protected

  ##
  ## UI METHODS FOR THE SHARE & NOTIFY FORMS
  ## 

  # given the params[:recipients] returns an options-hash for recipients
  def get_recipients_with_options(recipients_with_options)  
    options_with_recipients = {}
    recipients_with_options.each_pair do |recipient,options|
      if options.kind_of?(Hash)
        options_with_recipients[symbolize_options(options)] ||= []
        options_with_recipients[symbolize_options(options)] << recipient.sub(" ", "+")
      end
      @recipients ||= []
      @recipients << recipient
    end
    options_with_recipients   
  end

  
  def symbolize_options options
    return options unless options.respond_to?(:each)
    symbolized_options = {}
    options.each do |k,v|
      k.respond_to?(:to_sym) ? k = k.to_sym : k ;
      v.respond_to?(:to_sym) ? v = v.to_sym : v ;
      symbolized_options[k] = v
    end
    symbolized_options
  end

  def close_popup
    render :template => 'base_page/reset_sidebar'
  end

  def show_error_message
    render :template => 'base_page/show_errors'
  end

  def authorized?
    if action?('update_public','create','destroy', 'move','set_owner')
      current_user.may? :admin, @page
    else
      current_user.may? :view, @page
    end
  end

  prepend_before_filter :fetch_page
  def fetch_page
    if params[:page_id]
      @page = Page.find_by_id(params[:page_id])
      @upart = @page.participation_for_user(current_user)
    end
    true
  end

end
