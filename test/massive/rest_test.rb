# frozen_string_literal: true

require 'massive/rest'

describe Massive::REST do
  it "has a version number" do
    expect(Massive::REST::VERSION).not.to be_nil
  end
end
