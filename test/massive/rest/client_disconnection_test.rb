# frozen_string_literal: true

require 'massive/rest/client'
require 'sus/fixtures/async'

describe 'Massive::REST::Client disconnection at 100 requests' do
  include Sus::Fixtures::Async::ReactorContext

  let(:server_endpoint) { Async::HTTP::Endpoint.parse('http://localhost:9295', protocol: Async::HTTP::Protocol::HTTP2) }

  it 'makes 100+ requests with client self-disconnection after 99' do
    request_count = 0
    connection_count = 0
    mutex = Mutex.new
    last_connection = nil

    # Server that tracks connections and enforces 99 request limit per connection
    app = Protocol::HTTP::Middleware.for do |request|
      current_connection = request.connection

      mutex.synchronize do
        if current_connection != last_connection
          # New connection detected
          connection_count += 1
          last_connection = current_connection
          request_count = 1  # Reset counter for new connection
        else
          request_count += 1
        end

        # Server enforces max 99 requests per connection
        if request_count > 99
          current_connection&.close
          raise Errno::ECONNRESET, 'Connection limit exceeded'
        end
      end

      Protocol::HTTP::Response[200, {
        'content-type' => 'application/json'
      }, [JSON.generate({ status: 'OK', n: request_count, connection: connection_count })]]
    end

    server = Async::HTTP::Server.new(app, server_endpoint)
    server_task = Async { server.run }

    sleep 0.01  # Let server start

    original_level = Console.logger.level
    Console.logger.level = Console::Logger::ERROR

    # Temporarily replace the ENDPOINT constant to point to our test server
    original_endpoint = Massive::REST::Client::ENDPOINT
    Massive::REST::Client.send(:remove_const, :ENDPOINT)
    Massive::REST::Client.const_set(:ENDPOINT, server_endpoint)

    client = Massive::REST::Client.new(
      api_key: SecureRandom::alphanumeric(32),
      rate_limit: { requests: 99, window: 1 }
    )

    start = Async::Clock.now
    responses = []

    # Make 110 requests - client should self-disconnect after 99, wait, then reconnect
    110.times do |i|
      result = client.get_json("/test/#{i}")
      responses << result if result
    end

    elapsed = Async::Clock.now - start

    # Should complete in reasonable time
    expect(elapsed).to be < 2.0

    # Should have successfully made all 110 requests
    expect(responses.size).to be == 110

    # Should have used at least 2 connections (99 + 11)
    last_response = responses.last
    expect(last_response['connection']).to be >= 2

  ensure
    Console.logger.level = original_level if original_level
    Massive::REST::Client.send(:remove_const, :ENDPOINT) if defined?(Massive::REST::Client::ENDPOINT)
    Massive::REST::Client.const_set(:ENDPOINT, original_endpoint) if original_endpoint
    server_task&.stop
  end
end
