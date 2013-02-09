require "test_helper"
require 'capissh/file_transfers'

class FileTransfersTest < MiniTest::Unit::TestCase
  def setup
    @logger = stub_everything
    @configuration = stub("Configuration", :dry_run => false)
    @connection_manager = stub("ConnectionManager")
    @file_transfer = Capissh::FileTransfers.new(@configuration, @connection_manager, :logger => @logger)
    @servers = [server('cap1'), server('cap2')]
  end

  def test_put_should_delegate_to_upload
    @file_transfer.expects(:upload).with do |servers, from, to, opts|
      servers == @servers && from.string == "some data" && to == "test.txt" && opts == { :mode => 0777 }
    end
    @configuration.expects(:run).never
    @file_transfer.put(@servers, "some data", "test.txt", :mode => 0777)
  end

  def test_get_should_delegate_to_download_with_the_first_server_of_the_passed_servers
    @file_transfer.expects(:download).with(@servers.slice(0,1), "testr.txt", "testl.txt", :foo => "bar")
    @file_transfer.get(@servers, "testr.txt", "testl.txt", :foo => "bar")
  end

  def test_upload_should_delegate_to_transfer
    @file_transfer.expects(:transfer).with(@servers, :up, "testl.txt", "testr.txt", :foo => "bar")
    @file_transfer.upload(@servers, "testl.txt", "testr.txt", :foo => "bar")
  end

  def test_upload_without_mode_should_not_try_to_chmod
    @file_transfer.expects(:transfer).with(@servers, :up, "testl.txt", "testr.txt", :foo => "bar")
    @configuration.expects(:run).never
    @file_transfer.upload(@servers, "testl.txt", "testr.txt", :foo => "bar")
  end

  def test_upload_with_mode_should_try_to_chmod
    @file_transfer.expects(:transfer).with(@servers, :up, "testl.txt", "testr.txt", :foo => "bar")
    @configuration.expects(:run).with(@servers, "chmod 775 testr.txt", {:foo => "bar"})
    @file_transfer.upload(@servers, "testl.txt", "testr.txt", :mode => 0775, :foo => "bar")
  end

  def test_upload_with_symbolic_mode_should_try_to_chmod
    @file_transfer.expects(:transfer).with(@servers, :up, "testl.txt", "testr.txt", :foo => "bar")
    @configuration.expects(:run).with(@servers, "chmod g+w testr.txt", {:foo => "bar"})
    @file_transfer.upload(@servers, "testl.txt", "testr.txt", :mode => "g+w", :foo => "bar")
  end

  def test_upload_wont_transfer_if_dry_run
    @configuration.expects(:dry_run).returns(true)
    @connection_manager.expects(:execute_on_servers).never
    ::Capissh::Transfer.expects(:process).never
    @configuration.expects(:run).with(@servers, "chmod 775 testr.txt", {:foo => "bar"}) # this dry_runs also
    @file_transfer.upload(@servers, "testl.txt", "testr.txt", :mode => 0775, :foo => "bar")
  end

  def test_download_should_delegate_to_transfer
    @file_transfer.expects(:transfer).with(@servers, :down, "testr.txt", "testl.txt", :foo => "bar")
    @file_transfer.download(@servers, "testr.txt", "testl.txt", :foo => "bar")
  end

  def test_transfer_should_invoke_transfer_on_matching_servers
    @connection_manager.expects(:execute_on_servers).with(@servers, :foo => "bar").yields([:a, :b])
    Capissh::Transfer.expects(:process).with(:up, "testl.txt", "testr.txt", [:a, :b], {:foo => "bar", :logger => @logger})
    @file_transfer.transfer(@servers, :up, "testl.txt", "testr.txt", :foo => "bar")
  end

end
