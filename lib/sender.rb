module CatchException
	class Sender
    def rescue_action_in_public(exception)
    end

    include CatchException::Catcher
  end
end
