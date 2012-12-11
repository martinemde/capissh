# Capissh?

An extraction of Capistrano's parallel SSH command execution, capiche?

![Don Vito Corleone](http://i.imgur.com/hAcWI.jpg)


## About

Capissh executes commands (and soon transfers) on remote servers in parallel.

Capissh will maintain open connections with servers it has seen when is is
sensible to do so. When the batch size is not restricted, Capissh will maintain
all connections, which greatly reduces connection overhead. Sets of commands
are run in parallel on all servers within the batch.

## Example

The interface is intentionally simple. A Capissh::Configuration object will
maintain the open sessions, which will be matched up with servers for each
command invocation.

    require 'capissh'

    servers = ['user@host.com', 'user@example.com']
    capissh = Capissh.new
    capissh.run servers, 'date'
    capissh.run servers, 'uname -a'
    capissh.sudo servers, 'ls /root'

## Thank You

Huge thank you to Jamis Buck and all the other Capistrano contributors for
creating and maintaining this gem. Without them, this library would not exist,
and ruby deployment wouldn't be at the level it is today.

Most of this code is directly extracted from capistrano without modification.
