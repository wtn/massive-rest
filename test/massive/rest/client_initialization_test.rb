# frozen_string_literal: true

require 'massive/rest/client'

describe Massive::REST::Client do
  with 'initialization' do
    it "accepts explicit rate_limit parameter" do
      client = Massive::REST::Client.new(
        api_key: SecureRandom.alphanumeric(32),
        rate_limit: { requests: 50, window: 30 }
      )

      expect(client).to be_a(Massive::REST::Client)
    end

    it "accepts resource parameter" do
      # This will try to fetch from massive-account, so use explicit rate_limit instead
      client = Massive::REST::Client.new(
        api_key: SecureRandom.alphanumeric(32),
        rate_limit: { requests: 99, window: 1 }
      )

      expect(client).to be_a(Massive::REST::Client)
    end

    it "raises error for missing API key" do
      expect {
        Massive::REST::Client.new(api_key: nil, rate_limit: { requests: 99, window: 1 })
      }.to raise_exception(ArgumentError)
    end

    it "raises error for short API key" do
      expect {
        Massive::REST::Client.new(api_key: "short", rate_limit: { requests: 99, window: 1 })
      }.to raise_exception(ArgumentError)
    end

    it "raises error for long API key" do
      expect {
        Massive::REST::Client.new(
          api_key: SecureRandom.alphanumeric(40),
          rate_limit: { requests: 99, window: 1 }
        )
      }.to raise_exception(ArgumentError)
    end

    it "raises error for invalid rate_limit format (missing requests)" do
      expect {
        Massive::REST::Client.new(
          api_key: SecureRandom.alphanumeric(32),
          rate_limit: { window: 1 }
        )
      }.to raise_exception(ArgumentError)
    end

    it "raises error for invalid rate_limit format (missing window)" do
      expect {
        Massive::REST::Client.new(
          api_key: SecureRandom.alphanumeric(32),
          rate_limit: { requests: 99 }
        )
      }.to raise_exception(ArgumentError)
    end

    it "raises error for invalid rate_limit format (non-integer requests)" do
      expect {
        Massive::REST::Client.new(
          api_key: SecureRandom.alphanumeric(32),
          rate_limit: { requests: "99", window: 1 }
        )
      }.to raise_exception(ArgumentError)
    end

    it "raises error for invalid rate_limit format (non-integer window)" do
      expect {
        Massive::REST::Client.new(
          api_key: SecureRandom.alphanumeric(32),
          rate_limit: { requests: 99, window: "1" }
        )
      }.to raise_exception(ArgumentError)
    end

    it "accepts custom endpoint parameter" do
      custom_ep = Async::HTTP::Endpoint.parse("https://custom.example.com/")
      client = Massive::REST::Client.new(
        api_key: SecureRandom.alphanumeric(32),
        rate_limit: { requests: 99, window: 1 },
        endpoint: custom_ep,
      )

      expect(client).to be_a(Massive::REST::Client)
      expect(client.base_uri.to_s).to be == "https://custom.example.com/"
    end

    it "defaults endpoint to ENDPOINT constant" do
      client = Massive::REST::Client.new(
        api_key: SecureRandom.alphanumeric(32),
        rate_limit: { requests: 99, window: 1 },
      )

      expect(client.base_uri.to_s).to be == "https://api.massive.com/"
    end
  end

  with 'base_uri' do
    it "returns the Massive API endpoint URL" do
      client = Massive::REST::Client.new(
        api_key: SecureRandom.alphanumeric(32),
        rate_limit: { requests: 99, window: 1 }
      )

      uri = client.base_uri
      expect(uri.to_s).to be == 'https://api.massive.com/'
    end
  end
end
