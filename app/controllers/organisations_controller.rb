class OrganisationsController < ApplicationController

  # GET /organisation
  def show
    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html # show.html.erb
      format.json do
        json = JSON.parse @organisation.to_json

        json[:ldap_host] = current_organisation.value_by_key("ldap_host") || LdapBase.ensure_configuration["host"]
        json[:kerberos_realm] = @organisation.puavoKerberosRealm
        json[:puavo_domain] = @organisation.puavoDomain
        json[:base] = @organisation.base.to_s
        json[:kerberos_host] = current_organisation.value_by_key("kerberos_host") || LdapBase.ensure_configuration["host"]

        render :json => json
      end
    end
  end

  # GET /organisation/edit
  def edit
    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html
    end
  end

  # PUT /organisation
  def update
    @organisation = LdapOrganisation.current

    respond_to do |format|
      if @organisation.update_attributes(organisation_params)
        format.html { redirect_to( organisation_path ) }
      else
        format.html { render :action => "edit" }
      end
    end
  end

  # GET /organisation/wlan
  def wlan
    @organisation = LdapOrganisation.current

    respond_to do |format|
      format.html
    end
  end

  # PUT /organisation/wlan/update
  def wlan_update
    @organisation = LdapOrganisation.current

    @organisation.update_wlan_attributes( params[:wlan_name],
                                          params[:wlan_type],
                                          params[:wlan_password],
                                          params[:wlan_ap] )
    @organisation.puavoWlanChannel = params[:ldap_organisation][:puavoWlanChannel]

    respond_to do |format|
      if @organisation.save
        flash[:notice] = t('flash.wlan_updated')
        format.html { redirect_to( wlan_organisation_path ) }
      else
        flash[:alert] = t('flash.wlan_save_failed', :error => @organisation.errors["puavoWlanSSID"].first )
        format.html { render :action => "wlan" }
      end
    end
  end

  # GET /users/owners
  def owners

    @owners = LdapOrganisation.current.owner.select do |dn|
      dn != "uid=admin,o=puavo"
    end.map do |dn|
      User.find(dn)
    end

    @allowed_owners = User.find(:all,
                                :attribute => 'puavoEduPersonAffiliation',
                                :value => 'admin').delete_if do |u|
      @owners.include?(u)
    end

  end

  # PUT /users/add_owner/1
  def add_owner
    @user = User.find(params[:user_id])

    respond_to do |format|
      if not Array(@user.puavoEduPersonAffiliation).include?('admin')
        flash[:notice] = t('flash.organisation.wrong_user_type')
      elsif LdapOrganisation.current.add_owner(@user)
        flash[:notice] = t('flash.organisation.owner_added',
                           :user => @user.displayName )

      else
        
      end
      format.html { redirect_to(owners_organisation_path) }
    end
  end

  # PUT /users/remove_owner/1
  def remove_owner
    @user = User.find(params[:user_id])

    respond_to do |format|
      if LdapOrganisation.current.remove_owner(@user)
        flash[:notice] = t('flash.organisation.owner_removed',
                           :user => @user.displayName )
      end
      format.html { redirect_to(owners_organisation_path) }
    end
  end

  private
    def organisation_params
      return params.require(:ldap_organisation).permit(
        :o,
        :puavoEduOrgAbbreviation,
        :description,
        :telephoneNumber,
        :facsimileTelephoneNumber,
        :l,
        :street,
        :postOfficeBox,
        :postalAddress,
        :postalCode,
        :st,
        :puavoLocale,
        :puavoTimezone,
        :puavoKeyboardLayout,
        :puavoKeyboardVariant,
        :puavoAutomaticImageUpdates,
        :eduOrgHomePageURI,
        :puavoDeviceAutoPowerOffMode,
        :puavoDeviceOnHour,
        :puavoDeviceOffHour,
        :puavoDeviceImage,
        :puavoImageSeriesSourceURL=>[],
        :puavoBillingInfo=>[]
      ).to_hash
    end

end
