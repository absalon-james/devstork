import argparse
import os
import pprint
import yaml
import novaclient.exceptions
from novaclient.v1_1 import client


conf = None
osclient = None

def load_config(location):
    """
    Reads a yaml file and returns a dictionary.

    @param location - String file name
    @return Dict

    """
    global conf
    with open(location) as f:
        conf = yaml.safe_load(f)

def get_server():
    """
    Uses the nova client to query for a server.
    Uses the uuid saved in the file specified by the config.

    @returns Server|None

    """
    global osclient
    global conf

    if os.path.isfile(conf['id_file']):
        with open(conf['id_file']) as f:
            id_ = f.read()
        try:
            server = osclient.servers.get(id_)
            return server
        except novaclient.exceptions.NotFound:
            pass
    return None

def get_userdata():
    """
    Returns the contents of the userdata file specified by the config.

    @returns String
    
    """
    global conf
    userdata = None
    with open(conf['userdata_file'], 'r') as f:
        userdata = f.read()
    return userdata 

def create(args):
    """
    Creates the server if it doesn't already exist.
    If a server is created, it's uuid is saved to a file so that
    it can be deleted easily later.
   
    @params args - Args created by ArgParser
    """
    global osclient
    global conf

    server = get_server()
    if server:
        print "Server already exists:"
    else:
        print "Creating a new instance:"
        kwargs = {'key_name': conf['key_name']}

        # Add userdata
        userdata = get_userdata()
        if userdata:
            print "Adding userdata"
            kwargs['userdata'] = userdata

        server = osclient.servers.create(conf['name'],
                                         conf['image'],
                                         conf['flavor'],
                                         **kwargs)
    print "Server name: ", server.name
    print "Server id: ", server.id
    print "Networks: ", server.networks

    # Store server id to indicate server has been created
    with open(conf['id_file'], 'w') as f:
        f.write(server.id)

def delete(args):
    """
    Deletes the server if the file already exists.

    @param args - Args created by ArgParser

    """
    server = get_server()
    if server:
        server.delete()
        os.remove(conf['id_file'])
        print "Deleting server %s" % server.name
    else:
        print "Nothing to delete."

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Manage an OpenStack vm with configured flavor, image, and userdata.")
    parser.add_argument('--conf', type=str, help="location of yaml configuration file", default="conf.yaml")

    subparsers = parser.add_subparsers(title='subcommands')
    parser_create = subparsers.add_parser('create', help='Create the instance')
    parser_create.set_defaults(func=create)

    parser_delete = subparsers.add_parser('delete', help='Delete the instance')
    parser_delete.set_defaults(func=delete)

    args = parser.parse_args()

    # Load config
    load_config(args.conf)

    # Create Nova client
    osclient = client.Client(**conf.get('auth', {}))

    # Run the subcommand - either create or delete
    args.func(args)
