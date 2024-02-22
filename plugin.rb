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

  def after_authenticate(auth_token)
    # IFAD Customization to fetch all user information automatically from People
    #
    person = People::Client::Person.find(auth_token[:uid])

    #if the email address is set in the extra attributes and we know the accessor use it here
    email = auth_token[:extra][SiteSetting.cas_sso_email] if (auth_token[:extra] && auth_token[:extra][SiteSetting.cas_sso_email])
    #if we could not get the email address from the extra attributes try to set it base on the username
    email ||= unless SiteSetting.cas_sso_email_domain.nil?
      "#{auth_token[:uid]}@#{SiteSetting.cas_sso_email_domain}"
    else
      auth_token[:email] || auth_token[:uid]
    end

    user =
      User.where(username: person.account_name).first ||
      User.new(
        username: person.account_name,
            name: [person.first_name, person.last_name].join(' '),
           email: person.email,
         website: People::Client.client.config.base_uri + '/' + person.account_name,
           admin: false,
          active: true,
        approved: SiteSetting.cas_sso_user_approved
      ).tap(&:save!)

    user.update_column :bio_cooked, person.bio

    ::PluginStore.set("cas", "cas_uid_#{user.username}", {user_id: user.id})


    Auth::Result.new.tap do |result|
      result.email       = email
      result.email_valid = true

      result.username    = user.username
      result.name        = user.name
      result.extra_data  = { cas_user_id: user.username }

      result.user        = user
    end

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
              :message => 'Log in via CAS (Make sure pop up blockers are not enabled).',
              :frame_width => 920,
              :frame_height => 800,
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
