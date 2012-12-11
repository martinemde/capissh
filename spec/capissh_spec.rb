require 'spec_helper'

describe Capissh do
  it "runs commands" do
    con = Capissh::Connections.new
    con.run 'whoami'
  end
end
