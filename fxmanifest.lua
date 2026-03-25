fx_version "cerulean"
game "gta5"
lua54 "yes"

description "Mortar launcher"
version "1.0.0"

shared_scripts {
	"config.lua",
	"utls.lua",
}

client_scripts {
	"client.lua",
}

server_scripts {
	"server.lua",
}

dependencies {
	"community_bridge",
}

ui_page 'ui/index.html'

files {
	"stream/tube.ytyp",
    'locales/en.json',
    'locales/ar.json',
    'ui/index.html',
	'ui/pont.png',
}

data_file "DLC_ITYP_REQUEST" "stream/tube.ytyp"