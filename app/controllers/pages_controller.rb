class PagesController < ApplicationController
	allow_unauthenticated_access only: %i[ home ]

	def home
	end

	def dashboard
	end
end
