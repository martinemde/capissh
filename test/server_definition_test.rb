require 'test_helper'
require 'capissh/server_definition'

class ServerDefinitionTest < Minitest::Test
  def test_new_without_credentials_or_port_should_set_values_to_defaults
    server = Capissh::ServerDefinition.new("www.capissh.test")
    assert_equal "www.capissh.test", server.host
    assert_nil   server.user
    assert_nil   server.port
  end

  def test_new_with_encoded_user_should_extract_user_and_use_default_port
    server = Capissh::ServerDefinition.new("jamis@www.capissh.test")
    assert_equal "www.capissh.test", server.host
    assert_equal "jamis", server.user
    assert_nil   server.port
  end

  def test_new_with_encoded_port_should_extract_port_and_use_default_user
    server = Capissh::ServerDefinition.new("www.capissh.test:8080")
    assert_equal "www.capissh.test", server.host
    assert_nil   server.user
    assert_equal 8080, server.port
  end

  def test_new_with_encoded_user_and_port_should_extract_user_and_port
    server = Capissh::ServerDefinition.new("jamis@www.capissh.test:8080")
    assert_equal "www.capissh.test", server.host
    assert_equal "jamis", server.user
    assert_equal 8080, server.port
  end

  def test_new_with_user_as_option_should_use_given_user
    server = Capissh::ServerDefinition.new("www.capissh.test", :user => "jamis")
    assert_equal "www.capissh.test", server.host
    assert_equal "jamis", server.user
    assert_nil   server.port
  end

  def test_new_with_port_as_option_should_use_given_user
    server = Capissh::ServerDefinition.new("www.capissh.test", :port => 8080)
    assert_equal "www.capissh.test", server.host
    assert_nil   server.user
    assert_equal 8080, server.port
  end

  def test_encoded_value_should_override_hash_option
    server = Capissh::ServerDefinition.new("jamis@www.capissh.test:8080", :user => "david", :port => 8081)
    assert_equal "www.capissh.test", server.host
    assert_equal "jamis", server.user
    assert_equal 8080, server.port
    assert server.options.empty?
  end

  def test_new_with_option_should_dup_option_hash
    options = {}
    server = Capissh::ServerDefinition.new("www.capissh.test", options)
    refute_equal options.object_id, server.options.object_id
  end

  def test_new_with_options_should_keep_options
    server = Capissh::ServerDefinition.new("www.capissh.test", :primary => true)
    assert_equal true, server.options[:primary]
  end

  def test_default_user_should_try_to_guess_username
    #
    # No mocking framework at the moment
    #
    #ENV.stubs(:[]).returns(nil)
    #assert_equal "not-specified", Capissh::ServerDefinition.default_user

    #ENV.stubs(:[]).returns(nil)
    #ENV.stubs(:[]).with("USERNAME").returns("ryan")
    #assert_equal "ryan", Capissh::ServerDefinition.default_user

    #ENV.stubs(:[]).returns(nil)
    #ENV.stubs(:[]).with("USER").returns("jamis")
    #assert_equal "jamis", Capissh::ServerDefinition.default_user
  end

  def test_comparison_should_match_when_host_user_port_are_same
    s1 = server("jamis@www.capissh.test:8080")
    s2 = server("www.capissh.test", :user => "jamis", :port => 8080)
    assert_equal s1, s2
    assert_equal s1.hash, s2.hash
    assert s1.eql?(s2)
  end

  def test_servers_should_be_comparable
    s1 = server("jamis@www.capissh.test:8080")
    s2 = server("www.alphabet.test:1234")
    s3 = server("jamis@www.capissh.test:8075")
    s4 = server("billy@www.capissh.test:8080")

    assert s2 < s1
    assert s3 < s1
    assert s4 < s1
    assert s2 < s3
    assert s2 < s4
    assert s3 < s4
  end

  def test_comparison_should_not_match_when_any_of_host_user_port_differ
    s1 = server("jamis@www.capissh.test:8080")
    s2 = server("bob@www.capissh.test:8080")
    s3 = server("jamis@www.capissh.test:8081")
    s4 = server("jamis@app.capissh.test:8080")
    refute_equal s1, s2
    refute_equal s1, s3
    refute_equal s1, s4
    refute_equal s2, s3
    refute_equal s2, s4
    refute_equal s3, s4
  end

  def test_to_s
    assert_equal "www.capissh.test", server("www.capissh.test").to_s
    assert_equal "www.capissh.test", server("www.capissh.test:22").to_s
    assert_equal "www.capissh.test:1234", server("www.capissh.test:1234").to_s
    assert_equal "jamis@www.capissh.test", server("jamis@www.capissh.test").to_s
    assert_equal "jamis@www.capissh.test:1234", server("jamis@www.capissh.test:1234").to_s
  end
end

