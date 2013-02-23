require 'test_helper'
require 'capissh/transfer'
require 'capissh/sessions'

class TransferTest < MiniTest::Unit::TestCase
  def test_class_process_should_delegate_to_instance_process
    transfer = mock('transfer')
    transfer.expects(:call).with(%w(a b c))
    Capissh::Transfer.expects(:new).with(:up, "from", "to", {}).returns(transfer).yields
    yielded = false
    Capissh::Transfer.process(:up, "from", "to", %w(a b c), {}) { yielded = true }
    assert yielded
  end

  def test_default_transport_is_sftp
    transfer = Capissh::Transfer.new(:up, "from", "to")
    assert_equal :sftp, transfer.transport
  end

  def test_active_is_true_when_any_sftp_transfers_are_active
    sessions = MockSessions.new [session('app1', :sftp), session('app2', :sftp), session('app3', :sftp)]
    sessions.expects(:process_iteration).times(4).yields.returns(true,true,true,false)
    returns = [false, false, true]
    sessions.each do |s|
      txfr = mock('operation')
      txfr.expects(:active?).times(4).returns(returns.shift)
      s.xsftp.expects(:upload).returns(txfr)
    end
    transfer = Capissh::Transfer.new(:up, "from", "to", :via => :sftp)
    transfer.call(sessions)
  end

  def test_active_is_false_when_all_sftp_transfers_are_not_active
    sessions = MockSessions.new [session('app1', :sftp), session('app2', :sftp)]
    sessions.expects(:process_iteration).times(1).yields.returns(false)
    sessions.each do |s|
      txfr = mock('operation')
      txfr.expects(:active?).times(1).returns(false)
      s.xsftp.expects(:upload).returns(txfr)
    end
    transfer = Capissh::Transfer.new(:up, "from", "to", :via => :sftp)
    transfer.call(sessions)
  end

  def test_active_is_true_when_any_scp_transfers_are_active
    returns = [false, false, true]
    sessions = MockSessions.new [session('app1', :scp), session('app2', :scp), session('app3', :scp)]
    sessions.expects(:process_iteration).times(4).yields.returns(true,true,true,false)
    sessions.each do |s|
      channel = stub('channel', :[]= => nil, :[] => nil, :active? => returns.shift)
      s.scp.expects(:upload).returns(channel)
    end
    transfer = Capissh::Transfer.new(:up, "from", "to", :via => :scp)
    transfer.call(sessions)
  end

  def test_active_is_false_when_all_scp_transfers_are_not_active
    sessions = MockSessions.new [session('app1', :scp), session('app2', :scp), session('app3', :scp)]
    sessions.expects(:process_iteration).times(4).yields.returns(true,true,true,false)
    sessions.each do |s|
      channel = stub('channel', :[]= => nil, :[] => nil, :active? => false)
      s.scp.expects(:upload).returns(channel)
    end
    transfer = Capissh::Transfer.new(:up, "from", "to", :via => :scp)
    transfer.call(sessions)
  end

  [:up, :down].each do |direction|
    define_method("test_sftp_#{direction}load_from_file_to_file_should_normalize_from_and_to") do
      sessions = MockSessions.new [session('app1', :sftp), session('app2', :sftp)]
      sessions.expects(:process_iteration).times(1).yields.returns(false)

      sessions.each do |session|
        txfr = {}
        txfr.expects(:active?).returns(false)
        session.xsftp.expects("#{direction}load".to_sym).returns(txfr).with("from-#{session.xserver.host}", "to-#{session.xserver.host}",
          :properties => { :server => session.xserver, :host => session.xserver.host })
      end

      transfer = Capissh::Transfer.new(direction, "from-$CAPISSH:HOST$", "to-$CAPISSH:HOST$")
      transfer.call(sessions)
    end

    define_method("test_scp_#{direction}load_from_file_to_file_should_normalize_from_and_to") do
      sessions = MockSessions.new [session('app1', :scp), session('app2', :scp)]
      sessions.expects(:process_iteration).times(1).yields.returns(false)

      sessions.each do |session|
        channel = {}
        channel.expects(:active?).returns(false)
        session.scp.expects("#{direction}load".to_sym).returns(channel).with("from-#{session.xserver.host}", "to-#{session.xserver.host}", :via => :scp)
      end

      transfer = Capissh::Transfer.new(direction, "from-$CAPISSH:HOST$", "to-$CAPISSH:HOST$", :via => :scp)
      transfer.call(sessions)
    end
  end

  def test_sftp_upload_from_IO_to_file_should_clone_the_IO_for_each_connection
    sessions = MockSessions.new [session('app1', :sftp), session('app2', :sftp)]
    sessions.expects(:process_iteration).times(1).returns(false)
    io = StringIO.new("from here")

    sessions.each do |session|
      txfr = mock('operation')
      session.xsftp.expects(:upload).returns(txfr).with do |from, to, opts|
        from != io && from.is_a?(StringIO) && from.string == io.string &&
        to == "/to/here-#{session.xserver.host}" &&
        opts[:properties][:server] == session.xserver &&
        opts[:properties][:host] == session.xserver.host
      end
    end

    transfer = Capissh::Transfer.new(:up, StringIO.new("from here"), "/to/here-$CAPISSH:HOST$")
    transfer.call(sessions)
  end

  def test_scp_upload_from_IO_to_file_should_clone_the_IO_for_each_connection
    sessions = MockSessions.new [session('app1', :scp), session('app2', :scp)]
    sessions.expects(:process_iteration).times(1).returns(false)
    io = StringIO.new("from here")

    sessions.each do |session|
      channel = mock('channel')
      channel.expects(:[]=).with(:server, session.xserver)
      channel.expects(:[]=).with(:host, session.xserver.host)
      session.scp.expects(:upload).returns(channel).with do |from, to, opts|
        from != io && from.is_a?(StringIO) && from.string == io.string &&
        to == "/to/here-#{session.xserver.host}"
      end
    end

    transfer = Capissh::Transfer.new(:up, StringIO.new("from here"), "/to/here-$CAPISSH:HOST$", :via => :scp)
    transfer.call(sessions)
  end

  def test_process_should_block_until_transfer_is_no_longer_active
    sessions = MockSessions.new []
    sessions.expects(:process_iteration).times(4).yields.returns(true,true,true,false)
    transfer = Capissh::Transfer.new(:up, "from", "to")
    transfer.call(sessions)
  end

  def test_errors_raised_for_a_sftp_session_should_abort_session_and_continue_with_remaining_sessions
    s = session('app1', :sftp)
    error = ExceptionWithSession.new(s)
    sessions = MockSessions.new [s]
    sessions.expects(:process_iteration).raises(error).times(3).returns(true, false)
    transfer = Capissh::Transfer.new(:up, "from", "to")
    txfr = {}
    txfr.expects(:abort!).returns(true)
    s.xsftp.expects(:upload).with("from", "to", :properties => { :server => s.xserver, :host => s.xserver.host }).returns(txfr)
    assert_raises(Capissh::TransferError, "upload via sftp failed on server: TransferTest::ExceptionWithSession") do
      transfer.call(sessions)
    end
  end

  def test_errors_raised_for_a_scp_session_should_abort_session_and_continue_with_remaining_sessions
    s = session('app1', :scp)
    error = ExceptionWithSession.new(s)
    sessions = MockSessions.new [s]
    sessions.expects(:process_iteration).raises(error).times(3).returns(true, false)
    transfer = Capissh::Transfer.new(:up, "from", "to", :via => :scp)
    channel = {:server => 'server'}
    channel.expects(:close).returns(true)
    s.scp.expects(:upload).returns(channel)
    assert_raises(Capissh::TransferError, "upload via scp failed on server: TransferTest::ExceptionWithSession") do
      transfer.call(sessions)
    end
  end

  def test_uploading_a_non_existing_file_should_raise_an_understandable_error
    s = session('app1')
    error = Capissh::Sessions::SessionAssociation.on(ArgumentError.new('expected a file to upload'), s)
    transfer = Capissh::Transfer.new(:up, "from", "to", :via => :scp)
    sessions = MockSessions.new []
    sessions.expects(:process_iteration).raises(error)
    assert_raises(ArgumentError, 'expected a file to upload') { transfer.call(sessions) }
  end

  private

    class ExceptionWithSession < ::Exception
      attr_reader :session

      def initialize(session)
        @session = session
        super()
      end
    end

    class MockSessions < Array
      def process_iteration
        yield
      end
    end

    def session(host, mode=nil)
      session = stub('session', :xserver => server(host))
      case mode
      when :sftp
        sftp = stub('sftp')
        session.expects(:sftp).with(false).returns(sftp)
        sftp.expects(:connect).yields(sftp).returns(sftp)
        session.stubs(:xsftp).returns(sftp)
      when :scp
        session.stubs(:scp).returns(stub('scp'))
      end
      session
    end
end
