class BuildCloud::Instance

    include ::BuildCloud::Component

    @@objects = []

    def self.get_id_by_name( name )

        instance = self.search( :name => name ).first

        unless instance
            raise "Couldn't get an instance object for #{name} - is it defined?"
        end

        instance_fog = instance.read

        unless instance_fog
            raise "Couldn't get an instance fog object for #{name} - is it created?"
        end

        instance_fog.id

    end

    def initialize ( fog_interfaces, log, options = {} )

        @ec2     = fog_interfaces[:compute]
        @log     = log
        @options = options

        @log.debug( options.inspect )

        required_options(:image_id, :flavor_id, :private_ip_address, :name)
        require_one_of(:security_group_ids, :security_group_names, :network_interfaces)
        require_one_of(:subnet_id, :subnet_name, :network_interfaces)
        #require_one_of(:network_interfaces, :private_ip_address)
        require_one_of(:vpc_id, :vpc_name)

    end

    def ready_timeout
        5 * 60 # some instances (eg big EBS root vols) can take a while
    end

    def create
        
        return if exists?

        @log.info( "Creating instance #{@options[:name]}" )

        options = @options.dup

        if options[:security_group_names] or options[:security_group_ids]
            unless options[:security_group_ids]

                options[:security_group_ids] = []

                options[:security_group_names].each do |sg|
                    options[:security_group_ids] << BuildCloud::SecurityGroup.get_id_by_name( sg )
                end

                options.delete(:security_group_names)

            end
        end

        if options[:subnet_id] or options[:subnet_name]
            unless options[:subnet_id]

                options[:subnet_id] = BuildCloud::Subnet.get_id_by_name( options[:subnet_name] )
                options.delete(:subnet_name)

            end
        end

        unless options[:vpc_id]

            options[:vpc_id] = BuildCloud::VPC.get_id_by_name( options[:vpc_name] )
            options.delete(:vpc_name)

        end

        if options[:private_ip_address] and options[:network_interfaces]
            puts "WARNING: InvalidParameterCombination => Network interfaces and an instance-level private IP address should not be specified on the same request"
            puts "Using Network interface"
            options.delete(:private_ip_address)
        end

        if options[:subnet_id] and options[:network_interfaces]
            puts "WARNING: InvalidParameterCombination => Network interfaces and subnet_ids should not be specified on the same request"
            puts "Using Network interface"
            options.delete(:subnet_id)
        end

        options[:user_data] = JSON.generate( @options[:user_data] )

        options[:network_interfaces].each { |iface|
            if ! iface[:network_interface_name].nil?
                interface_id = BuildCloud::NetworkInterface.get_id_by_name( iface[:network_interface_name] )
                iface['NetworkInterfaceId'] = interface_id
                iface.delete(:network_interface_name)
            end
        } unless options[:network_interfaces].nil?

        @log.debug( options.inspect )

        instance = @ec2.servers.new( options )
        instance.save

        options[:tags].each do | tag |
            attributes = {}
            attributes[:resource_id] = instance.id.to_s
            attributes[:key] = tag[:key]
            attributes[:value] = tag[:value]
            new_tag = @ec2.tags.new( attributes )
            new_tag.save
        end unless options[:tags].empty? or options[:tags].nil?

        @log.debug( instance.inspect )

    end

    def read
        instances = @ec2.servers.select{ |l| l.tags['Name'] == @options[:name]}
        instances.select{ |i| i.state =~ /(running|pending)/ }.first
    end

    alias_method :fog_object, :read

    def delete

        return unless exists?

        @log.info( "Deleting instance #{@options[:name]}" )

        fog_object.destroy

    end

end
