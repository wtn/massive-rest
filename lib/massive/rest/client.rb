require 'async/http'
require 'massive/account'

module Massive
  module REST
    class Client
      ENDPOINT = Async::HTTP::Endpoint.parse 'https://api.massive.com/'

      # Initialize a new Massive REST API client
      #
      # @param api_key [String] Your Massive API key (defaults to ENV['MASSIVE_API_KEY'])
      # @param rate_limit [Hash, nil] Legacy parameter for single-resource rate limit
      #   Example: { requests: 99, window: 1 } for 99 requests per second
      # @param resource [Symbol, String] Legacy parameter, no longer used
      #
      # The client now automatically fetches rate limits for ALL subscribed resources
      # and applies the correct rate limit based on the request URI.
      def initialize(api_key: ENV['MASSIVE_API_KEY'], rate_limit: nil, resource: :stocks)
        api_key.to_s.length == 32 \
          or raise ArgumentError, 'API key required (32 characters)'

        @assets = fetch_all_assets(rate_limit)

        @semaphores = {}
        @reset_mutexes = {}
        @window_start_times = {}
        @assets.each do |res, asset_data|
          limit = asset_data[:rest_rate_limit]
          @semaphores[res] = {
            request: Async::Semaphore.new(limit[:requests]),
            completion: Async::Semaphore.new(limit[:requests])
          }
          @reset_mutexes[res] = Mutex.new
          @window_start_times[res] = Time.now
        end

        @auth_headers = {'authorization' => "Bearer #{api_key}"}
        @client = Async::HTTP::Client.new ENDPOINT
      end

      attr_reader :assets

      def base_uri
        ENDPOINT.to_url
      end

      def get_json(request_uri, resource: nil)
        resource ||= detect_resource_from_uri(request_uri)
        # Fall back to :stocks if resource not subscribed
        resource = :stocks unless @semaphores[resource]

        body = nil
        ensure_client_readiness(resource)
        @semaphores[resource][:request].acquire
        @semaphores[resource][:completion].acquire do
          Sync do
            if response = @client.get(request_uri, @auth_headers)
              body = response.read if response.ok? and response.headers['content-type'] == 'application/json'
              response.close
              Console.warn { "request failed status=#{response.status} request_uri=#{request_uri}" } if response.failure?
            end
          end
        end
        JSON.parse(body) if body
      end

      def get_json_array(request_uri, key: 'results')
        results = []
        while(request_uri) do
          if data = get_json(request_uri)
            results += data.fetch(key)
            request_uri = data['next_url'] && URI(data['next_url']).request_uri
          else
            request_uri = nil
          end
        end
        results
      end

      private

      def fetch_all_assets(rate_limit = nil)
        if rate_limit
          validate_rate_limit!(rate_limit)
          # When explicit rate_limit provided, create asset data for all resources
          asset_data = {
            websocket_connection_limit: 0,
            rest_rate_limit: rate_limit
          }
          return {
            stocks: asset_data,
            options: asset_data,
            futures: asset_data,
            indices: asset_data,
            forex: asset_data
          }
        end

        info = Massive::Account.info
        subscribed_assets = info[:assets] || {}

        # Use only the assets the user is actually subscribed to
        assets = {}
        subscribed_assets.each do |asset, data|
          # Map currency assets to forex for URI detection
          resource = asset.to_sym == :currencies ? :forex : asset.to_sym

          if data[:rest_rate_limit]
            assets[resource] = data
          else
            Console.warn(self) { "No rate limit found for #{resource}. Using default: 5 requests per 60 seconds" }
            assets[resource] = {
              websocket_connection_limit: 0,
              rest_rate_limit: { requests: 5, window: 60 }
            }
          end
        end

        # Ensure we have at least :stocks with a default if nothing was subscribed
        if assets.empty?
          Console.warn(self) { "No subscribed resources found. Using default rate limit for stocks: 5 requests per 60 seconds" }
          assets[:stocks] = {
            websocket_connection_limit: 0,
            rest_rate_limit: { requests: 5, window: 60 }
          }
        end

        assets
      end

      def validate_rate_limit!(rate_limit)
        unless rate_limit.is_a?(Hash) && rate_limit[:requests].is_a?(Integer) && rate_limit[:window].is_a?(Integer)
          raise ArgumentError, 'rate_limit must be a Hash with :requests and :window Integer keys'
        end
      end

      def detect_resource_from_uri(uri)
        case uri
        when %r{/v[23]/reference/tickers}, %r{/v2/aggs/ticker}, %r{/v3/trades}, %r{/v3/quotes}
          :stocks
        when %r{/v3/reference/options}, %r{/v3/snapshot/options}
          :options
        when %r{futures}
          :futures
        when %r{indices}
          :indices
        when %r{/v2/aggs/grouped/locale/global/market/fx}, %r{forex}, %r{/v2/aggs/grouped/locale/global/market/crypto}, %r{crypto}
          :forex
        else
          :stocks
        end
      end

      def ensure_client_readiness(resource)
        request_sem = @semaphores[resource][:request]
        completion_sem = @semaphores[resource][:completion]
        rate_limit = @assets[resource][:rest_rate_limit]

        if request_sem.blocking?
          @reset_mutexes[resource].synchronize do
            return if ! request_sem.blocking?

            elapsed = Time.now - @window_start_times[resource]
            remaining = rate_limit[:window] - elapsed

            rate_limit[:requests].times { completion_sem.acquire }
            @client.close
            sleep [remaining, 0].max

            @window_start_times[resource] = Time.now

            rate_limit[:requests].times { completion_sem.release }
            rate_limit[:requests].times { request_sem.release }
          end
        end
      end
    end
  end
end
