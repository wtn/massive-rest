# frozen_string_literal: true

require 'massive/rest/client'
require 'sus/fixtures/async'

describe 'Massive::REST::Client HTTP methods' do
  include Sus::Fixtures::Async::ReactorContext

  let(:server_endpoint) { Async::HTTP::Endpoint.parse('http://localhost:9297', protocol: Async::HTTP::Protocol::HTTP2) }
  let(:test_api_key) { SecureRandom.alphanumeric(32) }

  with '#get_json' do
    it 'makes GET request and parses JSON response' do
      request_path = nil
      request_headers = nil

      app = Protocol::HTTP::Middleware.for do |request|
        request_path = request.path
        request_headers = request.headers

        Protocol::HTTP::Response[200, {
          'content-type' => 'application/json'
        }, [JSON.generate({ status: 'OK', symbol: 'AAPL' })]]
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }

      sleep 0.01

      original_endpoint = Massive::REST::Client::ENDPOINT
      Massive::REST::Client.send(:remove_const, :ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, server_endpoint)

      client = Massive::REST::Client.new(
        api_key: test_api_key,
        rate_limit: { requests: 99, window: 1 }
      )

      result = client.get_json('/v3/reference/tickers/AAPL')

      expect(request_path).to be == '/v3/reference/tickers/AAPL'
      expect(request_headers['authorization']).to be == "Bearer #{test_api_key}"
      expect(result).to be == { 'status' => 'OK', 'symbol' => 'AAPL' }

    ensure
      Massive::REST::Client.send(:remove_const, :ENDPOINT) if defined?(Massive::REST::Client::ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, original_endpoint) if original_endpoint
      server_task&.stop
    end

    it 'returns nil for non-JSON response' do
      app = Protocol::HTTP::Middleware.for do |request|
        Protocol::HTTP::Response[200, {
          'content-type' => 'text/html'
        }, ['<html>Not JSON</html>']]
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }

      sleep 0.01

      original_endpoint = Massive::REST::Client::ENDPOINT
      Massive::REST::Client.send(:remove_const, :ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, server_endpoint)

      client = Massive::REST::Client.new(
        api_key: test_api_key,
        rate_limit: { requests: 99, window: 1 }
      )

      result = client.get_json('/test')

      expect(result).to be_nil

    ensure
      Massive::REST::Client.send(:remove_const, :ENDPOINT) if defined?(Massive::REST::Client::ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, original_endpoint) if original_endpoint
      server_task&.stop
    end

    it 'returns nil for failed request' do
      app = Protocol::HTTP::Middleware.for do |request|
        Protocol::HTTP::Response[404, {
          'content-type' => 'application/json'
        }, [JSON.generate({ error: 'Not Found' })]]
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }

      sleep 0.01

      original_endpoint = Massive::REST::Client::ENDPOINT
      Massive::REST::Client.send(:remove_const, :ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, server_endpoint)

      client = Massive::REST::Client.new(
        api_key: test_api_key,
        rate_limit: { requests: 99, window: 1 }
      )

      # Suppress expected warning for this test
      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      result = client.get_json('/test')

      expect(result).to be_nil

    ensure
      Console.logger.level = original_level if original_level
      Massive::REST::Client.send(:remove_const, :ENDPOINT) if defined?(Massive::REST::Client::ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, original_endpoint) if original_endpoint
      server_task&.stop
    end
  end

  with '#get_json_array' do
    it 'follows pagination with next_url' do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1

        case request_count
        when 1
          # First page with next_url
          Protocol::HTTP::Response[200, {
            'content-type' => 'application/json'
          }, [JSON.generate({
            results: [{ id: 1 }, { id: 2 }],
            next_url: 'https://api.massive.com/test?cursor=page2'
          })]]
        when 2
          # Second page without next_url
          Protocol::HTTP::Response[200, {
            'content-type' => 'application/json'
          }, [JSON.generate({
            results: [{ id: 3 }, { id: 4 }]
          })]]
        end
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }

      sleep 0.01

      original_endpoint = Massive::REST::Client::ENDPOINT
      Massive::REST::Client.send(:remove_const, :ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, server_endpoint)

      client = Massive::REST::Client.new(
        api_key: test_api_key,
        rate_limit: { requests: 99, window: 1 }
      )

      results = client.get_json_array('/test')

      expect(request_count).to be == 2
      expect(results.size).to be == 4
      expect(results[0]).to be == { 'id' => 1 }
      expect(results[3]).to be == { 'id' => 4 }

    ensure
      Massive::REST::Client.send(:remove_const, :ENDPOINT) if defined?(Massive::REST::Client::ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, original_endpoint) if original_endpoint
      server_task&.stop
    end

    it 'uses custom result key' do
      app = Protocol::HTTP::Middleware.for do |request|
        Protocol::HTTP::Response[200, {
          'content-type' => 'application/json'
        }, [JSON.generate({
          data: [{ id: 1 }, { id: 2 }]
        })]]
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }

      sleep 0.01

      original_endpoint = Massive::REST::Client::ENDPOINT
      Massive::REST::Client.send(:remove_const, :ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, server_endpoint)

      client = Massive::REST::Client.new(
        api_key: test_api_key,
        rate_limit: { requests: 99, window: 1 }
      )

      results = client.get_json_array('/test', key: 'data')

      expect(results.size).to be == 2
      expect(results[0]).to be == { 'id' => 1 }

    ensure
      Massive::REST::Client.send(:remove_const, :ENDPOINT) if defined?(Massive::REST::Client::ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, original_endpoint) if original_endpoint
      server_task&.stop
    end

    it 'returns empty array for failed request' do
      app = Protocol::HTTP::Middleware.for do |request|
        Protocol::HTTP::Response[404, {}, ['Not Found']]
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }

      sleep 0.01

      original_endpoint = Massive::REST::Client::ENDPOINT
      Massive::REST::Client.send(:remove_const, :ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, server_endpoint)

      client = Massive::REST::Client.new(
        api_key: test_api_key,
        rate_limit: { requests: 99, window: 1 }
      )

      # Suppress expected warning for this test
      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      results = client.get_json_array('/test')

      expect(results).to be == []

    ensure
      Console.logger.level = original_level if original_level
      Massive::REST::Client.send(:remove_const, :ENDPOINT) if defined?(Massive::REST::Client::ENDPOINT)
      Massive::REST::Client.const_set(:ENDPOINT, original_endpoint) if original_endpoint
      server_task&.stop
    end
  end
end
