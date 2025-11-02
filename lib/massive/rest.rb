require_relative "rest/version"
require_relative "rest/client"

module Massive
  module REST
    class Error < StandardError; end

    # Returns a memoized global client instance
    #
    # This is useful for the common single-account case where you want
    # to share one client across your application.
    #
    # @return [Client] The memoized client instance
    def self.client
      @client ||= Client.new
    end

    # Resets the memoized global client instance
    #
    # Primarily useful for testing when you need to clear the cached client.
    #
    # @return [nil]
    def self.reset_client!
      @client = nil
    end
  end
end
