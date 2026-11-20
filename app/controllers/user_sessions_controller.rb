# Where you are logged in. Only ever your own sessions.
class UserSessionsController < ApplicationController
  def index
    @sessions = current_user.sessions.order(Arel.sql("COALESCE(last_seen_at, created_at) DESC")).select(&:usable?)
  end

  def destroy
    session_row = current_user.sessions.find_by(id: params[:id])
    if session_row && session_row.id != Current.session.id
      session_row.destroy
      redirect_to sessions_list_path, notice: "Deze sessie is beëindigd."
    else
      redirect_to sessions_list_path, alert: "Deze sessie is niet gevonden. Je huidige sessie beëindig je met Uitloggen."
    end
  end

  def destroy_others
    current_user.sessions.where.not(id: Current.session.id).destroy_all
    redirect_to sessions_list_path, notice: "Je bent overal uitgelogd behalve hier."
  end
end
