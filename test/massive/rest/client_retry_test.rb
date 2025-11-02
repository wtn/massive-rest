# frozen_string_literal: true

require "massive/rest"
require "sus/fixtures/async"

describe "Massive::REST::Client retry logic" do
  include Sus::Fixtures::Async::ReactorContext

  let(:server_endpoint) { Async::HTTP::Endpoint.parse("http://localhost:9298", protocol: Async::HTTP::Protocol::HTTP2) }
  let(:test_api_key) { SecureRandom.alphanumeric(32) }

  def setup_client
    original_endpoint = Massive::REST::Client::ENDPOINT
    Massive::REST::Client.send(:remove_const, :ENDPOINT)
    Massive::REST::Client.const_set(:ENDPOINT, server_endpoint)

    client = Massive::REST::Client.new(
      api_key: test_api_key,
      rate_limit: { requests: 99, window: 1 },
    )

    [client, original_endpoint]
  end

  def restore_endpoint(original_endpoint)
    Massive::REST::Client.send(:remove_const, :ENDPOINT) if defined?(Massive::REST::Client::ENDPOINT)
    Massive::REST::Client.const_set(:ENDPOINT, original_endpoint) if original_endpoint
  end

  with "retriable status codes" do
    it "retries 504 Gateway Timeout and succeeds on retry" do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1
        if request_count == 1
          Protocol::HTTP::Response[504, {}, ["Gateway Timeout"]]
        else
          Protocol::HTTP::Response[200, {
            "content-type" => "application/json",
          }, [JSON.generate({ status: "OK" })]]
        end
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }
      sleep 0.01

      client, original_endpoint = setup_client

      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      result = client.get_json("/test")

      expect(request_count).to be == 2
      expect(result).to be == { "status" => "OK" }

    ensure
      Console.logger.level = original_level if original_level
      restore_endpoint(original_endpoint)
      server_task&.stop
    end

    it "retries 500 Internal Server Error" do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1
        if request_count <= 2
          Protocol::HTTP::Response[500, {}, ["Internal Server Error"]]
        else
          Protocol::HTTP::Response[200, {
            "content-type" => "application/json",
          }, [JSON.generate({ status: "OK" })]]
        end
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }
      sleep 0.01

      client, original_endpoint = setup_client

      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      result = client.get_json("/test")

      expect(request_count).to be == 3
      expect(result).to be == { "status" => "OK" }

    ensure
      Console.logger.level = original_level if original_level
      restore_endpoint(original_endpoint)
      server_task&.stop
    end

    it "retries 502 Bad Gateway" do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1
        if request_count == 1
          Protocol::HTTP::Response[502, {}, ["Bad Gateway"]]
        else
          Protocol::HTTP::Response[200, {
            "content-type" => "application/json",
          }, [JSON.generate({ status: "OK" })]]
        end
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }
      sleep 0.01

      client, original_endpoint = setup_client

      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      result = client.get_json("/test")

      expect(request_count).to be == 2
      expect(result).to be == { "status" => "OK" }

    ensure
      Console.logger.level = original_level if original_level
      restore_endpoint(original_endpoint)
      server_task&.stop
    end

    it "retries 503 Service Unavailable" do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1
        if request_count == 1
          Protocol::HTTP::Response[503, {}, ["Service Unavailable"]]
        else
          Protocol::HTTP::Response[200, {
            "content-type" => "application/json",
          }, [JSON.generate({ status: "OK" })]]
        end
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }
      sleep 0.01

      client, original_endpoint = setup_client

      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      result = client.get_json("/test")

      expect(request_count).to be == 2
      expect(result).to be == { "status" => "OK" }

    ensure
      Console.logger.level = original_level if original_level
      restore_endpoint(original_endpoint)
      server_task&.stop
    end

    it "retries 429 Too Many Requests" do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1
        if request_count == 1
          Protocol::HTTP::Response[429, {}, ["Too Many Requests"]]
        else
          Protocol::HTTP::Response[200, {
            "content-type" => "application/json",
          }, [JSON.generate({ status: "OK" })]]
        end
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }
      sleep 0.01

      client, original_endpoint = setup_client

      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      result = client.get_json("/test")

      expect(request_count).to be == 2
      expect(result).to be == { "status" => "OK" }

    ensure
      Console.logger.level = original_level if original_level
      restore_endpoint(original_endpoint)
      server_task&.stop
    end

    it "retries 408 Request Timeout" do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1
        if request_count == 1
          Protocol::HTTP::Response[408, {}, ["Request Timeout"]]
        else
          Protocol::HTTP::Response[200, {
            "content-type" => "application/json",
          }, [JSON.generate({ status: "OK" })]]
        end
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }
      sleep 0.01

      client, original_endpoint = setup_client

      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      result = client.get_json("/test")

      expect(request_count).to be == 2
      expect(result).to be == { "status" => "OK" }

    ensure
      Console.logger.level = original_level if original_level
      restore_endpoint(original_endpoint)
      server_task&.stop
    end
  end

  with "non-retriable status codes" do
    it "does not retry 404 Not Found" do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1
        Protocol::HTTP::Response[404, {
          "content-type" => "application/json",
        }, [JSON.generate({ error: "Not Found" })]]
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }
      sleep 0.01

      client, original_endpoint = setup_client

      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      result = client.get_json("/test")

      expect(request_count).to be == 1
      expect(result).to be_nil

    ensure
      Console.logger.level = original_level if original_level
      restore_endpoint(original_endpoint)
      server_task&.stop
    end

    it "does not retry 401 Unauthorized" do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1
        Protocol::HTTP::Response[401, {
          "content-type" => "application/json",
        }, [JSON.generate({ error: "Unauthorized" })]]
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }
      sleep 0.01

      client, original_endpoint = setup_client

      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      result = client.get_json("/test")

      expect(request_count).to be == 1
      expect(result).to be_nil

    ensure
      Console.logger.level = original_level if original_level
      restore_endpoint(original_endpoint)
      server_task&.stop
    end

    it "does not retry 400 Bad Request" do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1
        Protocol::HTTP::Response[400, {
          "content-type" => "application/json",
        }, [JSON.generate({ error: "Bad Request" })]]
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }
      sleep 0.01

      client, original_endpoint = setup_client

      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      result = client.get_json("/test")

      expect(request_count).to be == 1
      expect(result).to be_nil

    ensure
      Console.logger.level = original_level if original_level
      restore_endpoint(original_endpoint)
      server_task&.stop
    end
  end

  with "max retries exhausted" do
    it "raises Massive::REST::Error after max retries" do
      request_count = 0

      app = Protocol::HTTP::Middleware.for do |request|
        request_count += 1
        Protocol::HTTP::Response[504, {}, ["Gateway Timeout"]]
      end

      server = Async::HTTP::Server.new(app, server_endpoint)
      server_task = Async { server.run }
      sleep 0.01

      client, original_endpoint = setup_client

      original_level = Console.logger.level
      Console.logger.level = Console::Logger::ERROR

      # 1 initial + 3 retries = 4 total attempts, then raises
      expect do
        client.get_json("/test")
      end.to raise_exception(Massive::REST::Error, message: be =~ /after 4 attempts.*status=504/)

      expect(request_count).to be == 4

    ensure
      Console.logger.level = original_level if original_level
      restore_endpoint(original_endpoint)
      server_task&.stop
    end
  end
end
