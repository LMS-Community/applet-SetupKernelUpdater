--[[

Kernel Updater Meta - allow test kernels to be installed on fab4

(c) 2012, Adrian Smith, triode1@btinternet.com

based on FirmwareUpdater which is part of the jive core (c) Logitech

--]]

local oo            = require("loop.simple")
local AppletMeta    = require("jive.AppletMeta")
local System        = require("jive.System")
local appletManager = appletManager
local jiveMain      = jiveMain


module(...)
oo.class(_M, AppletMeta)


function jiveVersion(meta)
	return 1, 1
end


function registerApplet(meta)
	-- only for fab4, enable squeezeplay for test
	if System:getMachine() == "fab4" then
	--if System:getMachine() == "squeezeplay" then
		jiveMain:addItem(
			meta:menuItem('appletSetupKernelUpdater', 'advancedSettings', "Kernel Updater", function(applet, ...) applet:menu(...) end)
		)
	end
end


