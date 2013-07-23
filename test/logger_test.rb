require "test_helper"
require 'capissh/logger'
require 'stringio'

class LoggerTest < Minitest::Test
  def setup
    @io = StringIO.new
    # Turn off formatting for these tests. Formatting is tested in `logger_formatting_test.rb`.
    @logger = Capissh::Logger.new(:output => @io, :disable_formatters => true)
  end

  def test_logger_should_use_STDERR_by_default
    logger = Capissh::Logger.new
    assert_equal STDERR, logger.device
  end

  def test_logger_should_have_log_level_0
    logger = Capissh::Logger.new
    assert_equal 0, logger.level
  end

  def test_logger_should_use_level_form_options
    logger = Capissh::Logger.new :level => 4
    assert_equal 4, logger.level
  end

  def test_logger_should_use_output_option_if_output_responds_to_puts
    logger = Capissh::Logger.new(:output => STDOUT)
    assert_equal STDOUT, logger.device
  end

  def test_logger_should_open_file_if_output_does_not_respond_to_puts
    File.expects(:open).with("logs/capissh.log", "a").returns(:mock)
    logger = Capissh::Logger.new(:output => "logs/capissh.log")
    assert_equal :mock, logger.device
  end

  def test_close_should_not_close_device_if_device_is_default
    logger = Capissh::Logger.new
    logger.device.expects(:close).never
    logger.close
  end

  def test_close_should_not_close_device_is_device_is_explicitly_given
    logger = Capissh::Logger.new(:output => STDOUT)
    STDOUT.expects(:close).never
    logger.close
  end

  def test_close_should_close_device_when_device_was_implicitly_opened
    f = mock("file", :close => nil)
    File.expects(:open).with("logs/capissh.log", "a").returns(f)
    logger = Capissh::Logger.new(:output => "logs/capissh.log")
    logger.close
  end

  def test_log_with_level_greater_than_threshold_should_ignore_message
    @logger.level = 3
    @logger.log(4, "message")
    assert @io.string.empty?
  end

  def test_log_with_level_equal_to_threshold_should_log_message
    @logger.level = 3
    @logger.log(3, "message")
    assert @io.string.include?("message")
  end

  def test_log_with_level_less_than_threshold_should_log_message
    @logger.level = 3
    @logger.log(2, "message")
    assert @io.string.include?("message")
  end

  def test_log_with_multiline_message_should_log_each_line_separately
    @logger.log(0, "first line\nsecond line")
    assert @io.string.include?("*** first line")
    assert @io.string.include?("*** second line")
  end

  def test_log_with_line_prefix_should_insert_line_prefix_before_message
    @logger.log(0, "message", "prefix")
    assert @io.string.include?("*** [prefix] message")
  end

  def test_log_with_level_0_should_have_strong_indent
    @logger.log(0, "message")
    assert @io.string.match(/^\*\*\* message/)
  end

  def test_log_with_level_1_should_have_weaker_indent
    @logger.level = 1
    @logger.log(1, "message")
    assert @io.string.match(/^ \*\* message/)
  end

  def test_log_with_level_2_should_have_weaker_indent
    @logger.level = 2
    @logger.log(2, "message")
    assert @io.string.match(/^  \* message/)
  end

  def test_log_with_level_3_should_have_weakest_indent
    @logger.level = 3
    @logger.log(3, "message")
    assert @io.string.match(/^    message/)
  end

  def test_important_should_delegate_to_log_with_level_IMPORTANT
    @logger.expects(:log).with(Capissh::Logger::IMPORTANT, "message", "prefix")
    @logger.important("message", "prefix")
  end

  def test_info_should_delegate_to_log_with_level_INFO
    @logger.expects(:log).with(Capissh::Logger::INFO, "message", "prefix")
    @logger.info("message", "prefix")
  end

  def test_debug_should_delegate_to_log_with_level_DEBUG
    @logger.expects(:log).with(Capissh::Logger::DEBUG, "message", "prefix")
    @logger.debug("message", "prefix")
  end

  def test_trace_should_delegate_to_log_with_level_TRACE
    @logger.expects(:log).with(Capissh::Logger::TRACE, "message", "prefix")
    @logger.trace("message", "prefix")
  end

  def test_ordering_of_levels
    assert Capissh::Logger::IMPORTANT < Capissh::Logger::INFO
    assert Capissh::Logger::INFO < Capissh::Logger::DEBUG
    assert Capissh::Logger::DEBUG < Capissh::Logger::TRACE
  end
end
