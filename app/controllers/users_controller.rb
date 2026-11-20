class UsersController < ApplicationController
  before_action :require_current_account, only: :index
  before_action :require_explicit_fund_admin, only: %i[ destroy update ]

  def index
    # A link can name the fund (the redirect after an action does). The active memberships still decide.
    explicit = current_user.active_memberships.includes(:account).find_by(account_id: params[:account_id].to_s) if params[:account_id].present?
    @current_membership = explicit if explicit
    @account = current_account
    @users = @account.active_users.includes(:account_memberships, :wallets).order(:id)
    @duplicate_names = @account.duplicate_member_names
    @pending_invitations = @account.invitations.where(status: "pending")
    @rejected_invitations = @account.invitations.where(status: "rejected").order(updated_at: :desc)
    @total_members = @users.size
  end

  # Removes the app membership only. Their Safe ownership stays until a remove_owner proposal is
  # executed, so the admin is sent straight to that gap (docs/ARCHITECTURE.md, Authorization).
  def destroy
    account = @fund
    membership = account.account_memberships.active.find_by(user_id: params[:id])
    return redirect_to(users_path(account_id: account.id), alert: "Dit lid is niet gevonden.") unless membership
    return redirect_to(users_path(account_id: account.id), alert: "Jezelf verwijderen kan niet. Gebruik \"Fonds verlaten\" bij Instellingen.") if membership.user_id == current_user.id

    user = membership.user
    name = user.display_name
    removal = membership_removal(account, user)
    membership.destroy!
    cancelled = Chain::ProposalCancellation.for_departed(account, user, by: current_user)
    respond_to_removal(account, user, name, removal, cancelled)
  end

  # Admin, member or viewer. App roles carry no on-chain power, but a fund always keeps an admin.
  def update
    role = params[:role].to_s
    return redirect_to(users_path(account_id: @fund.id), alert: "Deze rol bestaat niet.") unless AccountMembership.roles.key?(role)

    outcome = @fund.with_lock do
      membership = @fund.account_memberships.active.find_by(user_id: params[:id])
      next :missing unless membership
      next :last_admin if membership.admin? && role != "admin" && @fund.admins.count == 1

      membership.update!(role: role)
      membership.user.update!(current_account: @fund) if membership.user_id == current_user.id
      :updated
    end

    case outcome
    when :missing then redirect_to users_path(account_id: @fund.id), alert: "Dit lid is niet gevonden."
    when :last_admin then redirect_to users_path(account_id: @fund.id), alert: "Een fonds heeft altijd minstens een admin. Maak eerst iemand anders admin."
    else redirect_after_role_change(role)
    end
  end

  private

  # Live owners against every wallet this person ever verified, so unlinking first does not hide anything.
  def membership_removal(account, user)
    return { owner: nil, checked: true } unless account.safe_active?

    live = Chain::SafeReader.for_account(account).owners
    { owner: (live & user.wallets.pluck(:address)).first, checked: true }
  rescue Chain::Rpc::Error, Chain::Registry::ChainDisabled
    { owner: nil, checked: false }
  end

  def respond_to_removal(account, user, name, removal, cancelled)
    note = cancelled.any? ? " #{helpers.pluralize_nl(cancelled.size, 'open voorstel', 'open voorstellen')} van deze persoon #{cancelled.size == 1 ? 'is' : 'zijn'} ingetrokken." : ""
    note += " Handtekeningen die al waren gezet blijven geldig op de blockchain totdat het volgnummer voorbij is." if cancelled.any? { |row| row.safe_signatures.any? }

    if removal[:owner]
      flash[:warning] = "#{name} is geen lid meer, maar kan op de blockchain nog steeds goedkeuren. Maak een voorstel om deze ondertekenaar te verwijderen.#{note}"
      redirect_to new_account_proposal_page_path(account, kind: "remove_owner", owner: removal[:owner])
    elsif !removal[:checked]
      flash[:warning] = "#{name} is geen lid meer, maar we konden niet controleren of deze persoon nog ondertekenaar is, omdat de blockchain niet bereikbaar is. Kijk dat na bij Transparantie.#{note}"
      redirect_to users_path(account_id: account.id)
    else
      redirect_to users_path(account_id: account.id), notice: "#{name} is geen lid meer van dit fonds.#{note}"
    end
  end

  def redirect_after_role_change(role)
    labels = { "admin" => "admin", "member" => "lid", "viewer" => "alleen lezen" }
    message = "Rol gewijzigd naar #{labels.fetch(role)}. Dit verandert niets op de blockchain: wie ondertekenaar is, blijft dat tot een voorstel dat wijzigt."
    # Whoever just gave up admin cannot see the admin-only page they came from.
    redirect_to users_path(account_id: @fund.id), notice: message
  end
end
