puts "Monkey patching LDAP schema caching. Assuming the activeldap gem version is 5.1.0."

# Because we do set the ldap connection manually for each request to the
# current users the defaul schema caching in ActiveLdap does not work because
# it gets reset when new connection is setup.
#
# Monkeypatch the cache to use global cache object which can be shared between
# multiple ldap connections
#
# XXX: This might not be thread safe. Currently it is not an issue because we
# deploy on Unicorn which is not multi threaded.
$active_ldap_schema_cache = {}
module ActiveLdap
  class Schema
    # https://github.com/activeldap/activeldap/blob/master/lib/active_ldap/schema.rb#L168-L171
    private
    def cache(key)
      ($active_ldap_schema_cache[key] ||= [yield])[0]
    end
  end
end
