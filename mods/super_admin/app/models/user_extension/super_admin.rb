module UserExtension
  module SuperAdmin
    def self.included(base)
      base.instance_eval do
        alias_method_chain :member_of?, :superadmin
        alias_method_chain :direct_member_of?, :superadmin
        alias_method_chain :friend_of?, :superadmin
        alias_method_chain :peer_of?, :superadmin
        alias_method_chain :may!, :superadmin
      end
    end
    
    # Returns true if self is a super admin. If self is the current_user
    # then no arguments are required. However, to test superadmin? on any
    # other user requires a site argument.
    def superadmin?(site=nil)
      site ||= self.current_site
      if site
        self.group_ids.include?(site.super_admin_group_id)
      else
        false
      end
    end

    def member_of_with_superadmin?(group)
      return true if superadmin?
      return member_of_without_superadmin?(group)
    end

    # is the user a direct member of the group?
    def direct_member_of_with_superadmin?(group)
      return true if superadmin?
      return direct_member_of_without_superadmin?(group)
    end

    def friend_of_with_superadmin?(user)
      return true if superadmin?
      return friend_of_without_superadmin?(user)
    end

    def peer_of_with_superadmin?(user)
      return true if superadmin?
      return peer_of_without_superadmin?(user)
    end

    def may_with_superadmin!(perm, object)
      return true if superadmin?
      return may_without_superadmin!(perm, object)
    end
  end 
end
