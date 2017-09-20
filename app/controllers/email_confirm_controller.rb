class EmailConfirmController < ApplicationController
  skip_before_filter  :find_school, :require_login, :require_puavo_authorization
  layout "password"

  # GET /users/email_confirm/:jwt
  def preview
    # validate jwt

    begin
      @jwt_data = JWT.decode(params[:jwt], Puavo::CONFIG["email_confirm_secret"])[0]

      respond_to do |format|
        format.html
      end

    rescue JWT::DecodeError
      @message_key = ".invalid_jwt_token"
      render :error
    end

  end

  # PUT /users/email_confirm
  def confirm
    begin

      jwt_data = JWT.decode(params[:jwt], Puavo::CONFIG["email_confirm_secret"])[0]

      perform_login( :uid => jwt_data["username"],
                     :organisation_key => organisation_key_from_host(jwt_data["organisation_domain"]),
                     :password => params[:email_confirm][:password] )

      User.ldap_modify_operation( current_user.dn,
                                  :replace, [{ "mail" => [jwt_data["email"]] }] )

      respond_to do |format|
        format.html { redirect_to( successfully_email_confirm_path ) }
      end

    rescue Puavo::AuthenticationFailed
      flash[:notice] = t('flash.email_confirm.invalid_password')
      redirect_to( preview_email_confirm_path(params[:jwt]) )
    rescue ActiveLdap::LdapError::TypeOrValueExists
      @message_key = ".email_already_exists"
      render :error
    rescue JWT::DecodeError
      @message_key = ".invalid_jwt_token"
      render :error
    end
  end

  def successfully

    respond_to do |format|
      format.html
    end
  end

end
