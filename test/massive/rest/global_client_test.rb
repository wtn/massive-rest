# frozen_string_literal: true

require 'massive/rest'

describe Massive::REST do
  with '#client' do
    it "returns a memoized client instance" do
      # Reset to ensure clean state
      Massive::REST.reset_client!

      client1 = Massive::REST.client
      client2 = Massive::REST.client

      expect(client1).to be_equal(client2)
    end
  end

  with '#reset_client!' do
    it "clears the memoized client" do
      # Get a client
      client1 = Massive::REST.client

      # Reset
      Massive::REST.reset_client!

      # Get a new client
      client2 = Massive::REST.client

      expect(client1).not.to be_equal(client2)
    end
  end
end
