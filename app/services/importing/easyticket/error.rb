module Importing
  module Easyticket
    class Error < StandardError; end
    class RequestError < Error; end
    class ParsingError < Error; end
    class RunAlreadyActiveError < Error; end
  end
end
