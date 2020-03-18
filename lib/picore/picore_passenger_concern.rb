# coding: utf-8
VALID_EMAIL_REGEX = /\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i
module PicorePassengerConcern
  extend ActiveSupport::Concern

  included do
    include Mongoid::Document
    include Mongoid::Timestamps
    include Mongoid::Paperclip
    include Mongoid::Attributes::Dynamic
    include SimpleEnum::Mongoid

    field :name
    field :email
    field :phone
    field :country_code_phone
    field :country_code
    field :password
    field :password_digest
    field :is_phone_validated, type: Boolean, default: false
    field :is_phone_validated2, type: Boolean, default: false
    field :fiscal_number

    as_enum :gender, {
      woman: 0,
      man: 1
    }, field: { type: Integer }

    before_validation :beautify_fields
    before_validation :setup_password_digest, unless: Proc.new{ |s| s.oauth_services.any? || s.fbmessenger_passenger }
    before_save :setup_password, unless: Proc.new{ |s| s.oauth_services.any? || s.fbmessenger_passenger }

    validates :name, presence: true, unless: Proc.new{ |s| s.fbmessenger_passenger }
    validates :email, presence: true, format: {with: VALID_EMAIL_REGEX}, uniqueness: {case_sesitive: false}, unless: Proc.new{ |s| s.fbmessenger_passenger }
    validates :phone, presence: true, unless: Proc.new{ |s| s.fbmessenger_passenger }
    validates :phone, :uniqueness => {:scope => [:is_phone_validated2, :country_code]}, allow_nil: true, unless: Proc.new{ |s| !s.is_phone_validated2 }
    validate  :password_presence, unless: Proc.new{ |s| s.oauth_services.any? || s.fbmessenger_passenger }

    # TODO borrar despues del 10.02.20 sin pensar ni preguntar =) @grigo
    # def name
    #   if self.fbmessenger_passenger
    #     self.fbmessenger_passenger.name
    #   else
    #     self['name']
    #   end
    # end

    def name
      self['name'] || fbmessenger_passenger&.name
    end

    # TODO borrar despues del 10.02.20 sin pensar ni preguntar =) @grigo
    # def phone
    #   if self.fbmessenger_passenger
    #     self.fbmessenger_passenger.phone
    #   else
    #     self['phone']
    #   end
    # end

    def phone
      self['phone'] || fbmessenger_passenger&.phone
    end

    def set_country_code_phone
      self.country_code_phone = "+#{self.full_phone}"
    end

    def full_phone
      "#{self.country_code}#{self.phone}"
    end

    def authenticate(password = nil)
      return self.class.authenticate((!self.email.blank? ? self.email : self.phone ), password)
    end

    def self.password_recovery email
      @passenger = Passenger.where( email: email.downcase.strip ).first if email
      return false, I18n.t("passenger.user_does_not_exist") unless @passenger
      return true, I18n.t("login.signing_facebook_btn") if @passenger.oauth_services.map{|a| a.provider == 'facebook'}.first
      return true, I18n.t("login.signing_google_btn") if @passenger.oauth_services.map{|a| a.provider == 'google_oauth2'}.first
      return @passenger.password_recovery
    end

    def continue_register
      return false, t('models.passenger.facebook_register') if oauth_services.any?
      continue_register_link
    end

    def continue_register_link
      link = burnable_links.new(link_for: "continue_register", use_limit: 10, expiration_date: Time.now + 364.days)
      return false, t('models.passenger.facebook_register') unless link.save
      PassengerMailer.delay.welcome_pihouse_resident(self)
      true
    end

    def self.authenticate(email = nil, password = nil, otp = nil)
      passenger = self.where(email: email.downcase.strip).first
      passenger = self.where(phone: email.downcase.strip, is_phone_validated2: true).first if !passenger
      passenger.update_attributes(password_digest: Digest::SHA256.hexdigest(passenger.password)) if passenger && passenger.is_admin && passenger.password_digest.nil? && passenger.password
      passenger.save if passenger && passenger.password_digest.nil?
      return passenger if passenger && (passenger.password_digest == Digest::SHA256.new.hexdigest(password)) && (otp.nil? || otp.present? && passenger.last_otp && passenger.last_otp.otp == Digest::SHA256.hexdigest(otp))
      passenger.last_otp.counter += 1 if otp.present? && passenger.last_otp != Digest::SHA256.new.hexdigest(otp)
      temporary_credentials = TemporaryPassword.where(email: email.downcase.strip).last
      return temporary_credentials.passenger if temporary_credentials && temporary_credentials.is_valid_password(password)
      nil
    end

    def self.signin device_params, session_params={}, oauth_params={}
      passenger = nil
      login_with_email = false
      if !session_params[:email].blank? && !session_params[:password].blank?
        login_with_email = true
        passenger = self.authenticate(session_params[:email], session_params[:password], session_params[:otp])
      elsif !oauth_params[:provider].blank? && !oauth_params[:token].blank?
        if oauth_params[:provider] == 'google_oauth2'
          login_with_email = true
          passenger = Passenger.where(email: oauth_params[:email]).first if oauth_params[:email].present?
        elsif oauth_params[:provider] == 'facebook'
          @graph = Koala::Facebook::API.new oauth_params[:token]
          @passenger_data_from_third = @graph.get_object("me", fields: ["email","name"])
          @passenger_data_from_third['uid'] = @passenger_data_from_third.delete 'id'
          oauth = OauthService.where(provider: oauth_params[:provider], uid: @passenger_data_from_third['uid'] ).first
          passenger = oauth.passenger if oauth
        end
      else
        return false, { mssg: "Parámetros inválidos"}
      end

      if passenger
        session =  passenger.sessions.create!(device_params)
        if !session_params[:email].blank? && !session_params[:password].blank?
          temporary_credentials = TemporaryPassword.where(email: session_params[:email].downcase.strip).last
          session.temporary_password = temporary_credentials if temporary_credentials && temporary_credentials.is_valid
          session.save
        end
        return true, session
      else
        if login_with_email
          return false, { mssg: "Usuario o contraseña inválidos"}
        else
          @passenger_data_from_third['token'] = oauth_params[:token]
          @passenger_data_from_third['provider'] = oauth_params[:provider]
          return false, @passenger_data_from_third
        end
      end
    end

    def logout
      session = last_session
      if session && session.clear_session_token
        return true, I18n.t('models.session.logout_successful')
      else
        return false, I18n.t('models.session.logout_failed')
      end
    end
  end

  def setup_password_digest
    if !self.password.blank?
      self.password_digest = Digest::SHA256.new.hexdigest(self.password.to_s)
    end
  end

  def setup_password
    self.password = nil
  end

  def password_presence
    if self.password && self.password.length < 6
        self.errors.add(
          :password,
          (
            I18n.t("models.password_length_greater_than", number: 6)
          )
        )
    elsif self.password && (self.password_digest && Digest::SHA256.new.hexdigest(self.password.to_s) != self.password_digest)
      self.errors.add(
        :password,
        (
          I18n.t("models.password_cant_be_blank")
        )
      )
    elsif self.password_digest.blank?
      self.errors.add(
        :password,
        (
          I18n.t("models.password_cant_be_blank")
        )
      )
    end
    self.password = nil
  end

  def beautify_fields
    self.email = self.email.downcase.strip if self.email
    self.phone = self.phone.scan(/\d/).join if self.phone
    self.fiscal_number = self.fiscal_number.strip.gsub(/[^0-9a-z]/i, '').upcase if self.fiscal_number
  end

  def password_recovery
    link = self.burnable_links.new(link_for: "password_recovery", use_limit: 6)
    return false, %{
      Ya habíamos enviado un email con las instrucciones para recuperar tu contraseña. Encuéntralo en tu correo.
    } if !link.save
    PassengerMailer.password_recovery(self).deliver_now!
    return true, "Hemos enviado un mail a #{self.email} con instrucciones para reestablecer tu contraseña"
  end

end
