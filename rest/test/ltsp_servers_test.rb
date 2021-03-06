require "fileutils"
require_relative "./helper"

describe PuavoRest::LtspServers do


  before(:each) do
    Puavo::Test.clean_up_ldap
    PuavoRest::LtspServer.local_store.flushdb
    FileUtils.rm_rf CONFIG["ltsp_server_data_dir"]

    @school = School.create(
      :cn => "gryffindor",
      :displayName => "Gryffindor"
    )
  end

  after(:each) do
    Timecop.return
  end

  it "responds with empty data" do
    get "/v3/ltsp_servers"
    assert_equal "[]", last_response.body
  end

  it "does not list boot servers as ltsp servers" do
    create_server(
      :puavoHostname => "evilbootserver",
      :puavoDeviceType => "bootserver",
      :macAddress => "00:60:2f:37:6C:DE"
    )

    get "/v3/ltsp_servers"
    assert_equal "[]", last_response.body

    get "/v3/ltsp_servers/evilbootserver"
    assert_equal 404, last_response.status, last_response.body
  end

  it "has tags and timezone" do
    create_server(
      :puavoHostname => "ltsptagsserver",
      :macAddress => "00:60:2f:5F:08:97",
      :puavoTag => ["tag1", "tag2"]
    )

    get "/v3/ltsp_servers/ltsptagsserver"
    assert_200

    data = JSON.parse(last_response.body)
    assert data["tags"], "has tags"
    assert_equal "tag1", data["tags"][0]
    assert_equal "tag2", data["tags"][1]
    assert_equal "Europe/Helsinki", data["timezone"]
  end

  it "responds 404 for unknown servers" do
    put "/v3/ltsp_servers/unknownserver",
      "load_avg" => "1.0",
      "cpu_count" => 1

    assert_equal 404, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal("NotFound", data["error"]["code"])
  end

  it "can set load average" do
    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71"
    )

    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0"
    get "/v3/ltsp_servers/testserver"
    data = JSON.parse(last_response.body)
    assert_equal 200, last_response.status
    assert_in_delta 1.0, data["state"]["load_avg"], 0.01
  end

  it "respond 400 to 0 cpu_count" do
    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71"
    )

    put "/v3/ltsp_servers/testserver", "load_avg" => "3.13", "cpu_count" => "0"
    data = JSON.parse(last_response.body)
    assert_equal 400, last_response.status
    assert_equal(
      {"error"=>{"code"=>"BadInput", "message"=>"0 cpu_count makes no sense"}},
      data
    )

  end

  it "can set load average with cpu_count" do
    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71"
    )

    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0", "cpu_count" => 2
    get "/v3/ltsp_servers/testserver"
    data = JSON.parse(last_response.body)
    assert_in_delta 0.5, data["state"]["load_avg"], 0.01
  end

  it "can will contain school data if set" do
    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71",
      :puavoSchool => @school.dn
    )

    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0", "cpu_count" => 2
    get "/v3/ltsp_servers/testserver"
    data = JSON.parse(last_response.body)
    assert_equal @school.dn, data["school_dns"].first
  end

  it "can return only the most idle sever" do
    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71"
    )
    create_server(
      :puavoHostname => "idleserver",
      :macAddress => "bc:5f:f4:56:59:72"
    )

    put "/v3/ltsp_servers/testserver", "load_avg" => "1.0", "cpu_count" => 2
    put "/v3/ltsp_servers/idleserver", "load_avg" => "0.2", "cpu_count" => 2

    get "/v3/ltsp_servers/_most_idle"
    data = JSON.parse(last_response.body)
    assert_equal "idleserver", data["hostname"]
  end

  it "_most_idle filters out old servers" do
    create_server(
      :puavoHostname => "oldserver",
      :macAddress => "bc:5f:f4:56:59:71"
    )
    create_server(
      :puavoHostname => "newserver",
      :macAddress => "bc:5f:f4:56:59:72"
    )

    put "/v3/ltsp_servers/oldserver", "load_avg" => "0.2", "cpu_count" => 2
    Timecop.travel 60 * 5
    put "/v3/ltsp_servers/newserver", "load_avg" => "1.2", "cpu_count" => 2

    get "/v3/ltsp_servers/_most_idle"
    data = JSON.parse(last_response.body)
    assert_equal "newserver", data["hostname"]
  end

  it "has mountpoints by schools" do
    @school2 = School.create(
      :cn => "exampl2",
      :displayName => "Example school 2",
      :puavoMountpoint => '{"fs":"nfs3","path":"10.0.0.2/share","mountpoint":"/home/school3/share","options":"-o r"}'
    )

    @school3 = School.create(
      :cn => "exampl3",
      :displayName => "Example school 3",
      :puavoMountpoint => '{"fs":"nfs4","path":"10.0.0.3/share","mountpoint":"/home/school3/share","options":"-o r"}'   )

    create_server(
      :puavoHostname => "testserver",
      :macAddress => "bc:5f:f4:56:59:71",
      :puavoSchool => [ @school2.dn, @school3.dn ]
    )

    get "/v3/ltsp_servers/testserver"
    data = JSON.parse(last_response.body)

    correct_mountpoints = [ { "fs" => "nfs3",
                              "path" => "10.0.0.2/share",
                              "mountpoint" => "/home/school3/share",
                              "options" => "-o r" },
                            { "fs" => "nfs4",
                              "path" => "10.0.0.3/share",
                              "mountpoint" => "/home/school3/share",
                              "options" => "-o r" } ].sort{ |a,b| a.to_s <=> b.to_s }
    data_mountpoints = data["mountpoints"].sort{ |a,b| a.to_s <=> b.to_s }

    assert_equal( correct_mountpoints,
                  data_mountpoints )

  end
end
