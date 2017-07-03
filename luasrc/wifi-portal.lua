#!/usr/bin/lua

local ev = require "ev"
local evmg = require "evmongoose"
local cjson = require "cjson"
local log = require "wifi-portal.log"
local conf = require "wifi-portal.conf"
local util = require "wifi-portal.util"
local http = require "wifi-portal.http"
local ping = require "wifi-portal.ping"

local ARGV = arg
local only_show_conf

local mgr = evmg.init()

function usage()
	print("Usage:", ARGV[0], "options")
	print([[
        -s              Only show config
        -d              Log to stderr
        -i              default is eth0
        -c              Config file path
	]])
	os.exit()
end

local function parse_commandline()
	local longopt = {
		{"help", nil, 'h'}
	}
	
	for o, optarg, lo, in util.getopt(ARGV, "hsdi:c:", longopt) do
		if o == '?' or o == "h" then
			usage()
		end
		
		if o == "d" then
			conf.log_to_stderr = true
		elseif o == "i" then
			conf.ifname = optarg
		elseif o == "s" then
			only_show_conf = true
		elseif o == "c" then
			conf.file = optarg
		else
			usage()
		end
	end
end

local function ev_handle(nc, event, msg)
	if event == evmg.MG_EV_HTTP_REQUEST then
		return http.dispach(mgr, nc, msg)
	end
end

local function init_log()
	local option = log.syslog.LOG_ODELAY

	if conf.log_to_stderr then
		option = option + log.syslog.LOG_PERROR 
	end
	log.open("wifi-portal", option, log.syslog.LOG_USER)
end

local function main()
	local loop = ev.Loop.default
	
	parse_commandline()
	conf.parse_conf()
	
	if only_show_conf then conf.show() end

	init_log()

	ev.Signal.new(function(loop, sig, revents)
		loop:unloop()
	end, ev.SIGINT):start(loop)

	util.add_trusted_ip(conf.authserv_hostname)
	
	mgr:bind(conf.gw_port, ev_handle, {proto = "http"})
	mgr:bind(conf.gw_ssl_port, ev_handle, {proto = "http", ssl_cert = "/etc/wifi-portal/wp.crt", ssl_key = "/etc/wifi-portal/wp.key"})

	ping.start(mgr, loop)

	log.info("start...")
	log.info("Listen on http:", conf.gw_port)
	log.info("Listen on https:", conf.gw_ssl_port)
	
	loop:loop()
	
	mgr:destroy()	
	log.info("exit...")

	log.close()
end

main()

