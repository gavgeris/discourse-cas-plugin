# name: CAS
# about: Authenticate with discourse with CAS
# version: 0.1.2
# author: Erik Ordway
require 'rubygems'


#addressable is set to require: false as the cas code will
# load the actual part that it needs at runtime.
gem 'eriko-omniauth-cas', '1.0.5' ,require_name: 'omniauth-cas'


class CASAuthenticator < ::Auth::Authenticator


  def name
    'cas'
  end

  def enabled?
    true
  end

  def after_authenticate(auth_token)
    # IFAD Customization to fetch all user information automatically from People
    #
    result = Auth::Result.new
   log(
      "after_authenticate response: \n\ncreds: #{auth_token["credentials"].to_hash}\nuid: #{auth_token["uid"]}\ninfo: #{auth_token["info"].to_hash}\nextra: #{auth_token["extra"].to_hash}",
    )

    #if the email address is set in the extra attributes and we know the accessor use it here
    email = auth_token[:extra][SiteSetting.cas_sso_email] if (auth_token[:extra] && auth_token[:extra][SiteSetting.cas_sso_email])

#     tokenemail = auth_token[:extra][SiteSetting.cas_sso_email]
#     log("email: #{tokenemail}")
#     tokenemail = auth_token["extra"]["email"]
#     log("email2: #{tokenemail}")


    #if we could not get the email address from the extra attributes try to set it base on the username
    email ||= unless SiteSetting.cas_sso_email_domain.nil?
              "#{auth_token[:uid]}@#{SiteSetting.cas_sso_email_domain}"
            else
              auth_token[:email] || auth_token[:uid]
            end

    result.email = email
    result.email_valid = true
    result.username = auth_token[:uid]

    result.name = if auth_token[:extra] && auth_token[:extra][SiteSetting.cas_sso_name]
                    auth_token[:extra][SiteSetting.cas_sso_name]
                  else
                    auth_token[:uid]
                  end
     # plugin specific data storage
     current_info = ::PluginStore.get("cas", "cas_uid_#{result.username}")

     if SiteSetting.cas_sso_user_auto_create && User.find_by_email(email).nil?
      user = User.create(name: result.name,
                       email: result.email,
                       username: result.username,
                       approved: SiteSetting.cas_sso_user_approved)
      ::PluginStore.set("cas", "cas_uid_#{user.username}", {user_id: user.id})
      result.email_valid = true
    end

    result.user =
       if current_info
          User.where(id: current_info[:user_id]).first
       elsif user = User.where(username: result.username).first
          #here we get a user that has already been created but has never logged in with cas. This
          # could happen if accounts are being pre provisionsed in an edu environment. We
          #need to get the users and set the cas plugin information as in after_create_account
          user.update_attribute(:approved, SiteSetting.cas_sso_user_approved)
          ::PluginStore.set("cas", "cas_uid_#{result.username}", {user_id: user.id})
          user
       end
#     result.user ||= User.where(email: email).first
    result.user ||= User.find_by_email(email)

    result
  end

  def log(info)
    Rails.logger.warn("CAS Plugin Debugging: #{info}")
  end

  def after_create_account(user, auth)
    user.update_attribute(:approved, SiteSetting.cas_sso_user_approved)
    ::PluginStore.set("cas", "cas_uid_#{auth[:username]}", {user_id: user.id})
  end


  def register_middleware(omniauth)
    unless SiteSetting.cas_sso_url.empty?
      omniauth.provider :cas,
                        :setup => lambda { |env|
                          strategy = env["omniauth.strategy"]
                          strategy.options[:url] = SiteSetting.cas_sso_url
                        }
    else
      omniauth.provider :cas,
                        :setup => lambda { |env|
                          strategy = env["omniauth.strategy"]
                          strategy.options[:host] = SiteSetting.cas_sso_host
                          strategy.options[:port] = SiteSetting.cas_sso_port
                          strategy.options[:path] = SiteSetting.cas_sso_path
                          strategy.options[:ssl] = SiteSetting.cas_sso_ssl
                          strategy.options[:service_validate_url] = SiteSetting.cas_sso_service_validate_url
                          strategy.options[:login_url] = SiteSetting.cas_sso_login_url
                          strategy.options[:logout_url] = SiteSetting.cas_sso_logout_url
                          strategy.options[:uid_field] = SiteSetting.cas_sso_uid_field
                        }
    end
  end
end


auth_provider :title => 'with CAS',
#               :message => 'Log in via CAS (Make sure pop up blockers are not enabled).',
#               :frame_width => 920,
#               :frame_height => 800,
              :authenticator => CASAuthenticator.new


register_css <<CSS

.btn-social.cas {
  background: #70BA61;
}

.btn-social.cas:before {
  font-family: Ubuntu;
  content: "C";
}

CSS
