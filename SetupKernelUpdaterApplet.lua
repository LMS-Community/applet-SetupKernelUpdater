--[[

Kernel Updater - allow test kernels to be installed on fab4

(c) 2012, Adrian Smith, triode1@btinternet.com

based on FirmwareUpdater which is part of the jive core (c) Logitech

--]]


local oo               = require("loop.simple")
local io               = require("io")
local lom              = require("lxp.lom")

local RequestHttp      = require("jive.net.RequestHttp")
local SocketHttp       = require("jive.net.SocketHttp")
local SocketTcp        = require("jive.net.SocketTcp")

local Applet           = require("jive.Applet")
local System           = require("jive.System")
local Framework        = require("jive.ui.Framework")
local Icon             = require("jive.ui.Icon")
local Label            = require("jive.ui.Label")
local Tile             = require("jive.ui.Tile")
local SimpleMenu       = require("jive.ui.SimpleMenu")
local Slider           = require("jive.ui.Slider")
local Surface          = require("jive.ui.Surface")
local Task             = require("jive.ui.Task")
local Textarea         = require("jive.ui.Textarea")
local Window           = require("jive.ui.Window")
local Popup            = require("jive.ui.Popup")
local KernelUpgrade    = require("applets.SetupKernelUpdater.KernelUpgrade")

local debug            = require("jive.utils.debug")

local jnt              = jnt
local jiveMain         = jiveMain
local appletManager    = appletManager

local STOP_SERVER_TIMEOUT = 10

local ipairs, type = ipairs, type

module(..., Framework.constants)
oo.class(_M, Applet)


-- find test kernels from this url
local kernels = "http://ralph.irving.sdf.org/edo/fab4-kernels.xml"


function menu(self, menuItem)
	self.window = Window("text_list", "Select Kernel")
	self.menu = SimpleMenu("menu")
	self.window:addWidget(self.menu)

	local req = RequestHttp(
		function(chunk)
			if chunk then
				local xml = lom.parse(chunk)
				for _, t in ipairs(xml) do
					if type(t) == "table" and t.tag == "kernel" then
						self:_addOption(t)
					end
				end
			end
		end
		, 'GET', kernels)
	local uri = req:getURI()
	local http = SocketHttp(jnt, uri.host, uri.port, uri.host)
	http:fetch(req)

	self:tieAndShowWindow(self.window)
	return window
end


function _addOption(self, t)
	local title, desc
	local url = t.attr.url
	local md5 = t.attr.md5

	for _, v in ipairs(t) do
		if type(v) == "table" and v.tag then
			if v.tag == "title" then
				title = v[1]
			elseif v.tag == "desc" then
				desc = v[1]
			end
		end
	end

	desc = desc .. "\nInstall at your own risk"

	self.menu:addItem({
		text = title,
		sound = "WINDOWSHOW",
		callback = function(event, menuItem)
			window = Window("text_list", menuItem.text)
			menu = SimpleMenu("menu")
			window:addWidget(menu)
			menu:setHeaderWidget(Textarea("help_text", desc))
			menu:addItem({
				text = "Install Kernel",
				sound = "WINDOWSHOW",
				callback = function(event, menuItem)
							   self:_upgrade(url, md5)
						   end
			})
			menu:addItem({
				text = "Cancel",
				sound = "WINDOWHIDE",
				callback = function()
							   window:hide()
						   end,
			})
			self:tieAndShowWindow(window)
		end,
	})
end


--------------------------------------------------------------------------------------------------------------------------------
-- following is modified form of SetupFirmwareUpgrade

function _upgrade(self, url, md5)
	self.url = url
	self.md5 = md5

	self.popup = Popup("update_popup")
	self.icon = Icon("icon_software_update")
	self.popup:addWidget(self.icon)

	self.text = Label("text", "Downloading", "")
	self.counter = Label("subtext", "")
	self.progress = Slider("progress", 1, 100, 1)

	self.popup:addWidget(self.text)
	self.popup:addWidget(self.counter)
	self.popup:addWidget(self.progress)
	self.popup:focusWidget(self.text)

	-- make sure this popup remains on screen
	self.popup:setAllowScreensaver(false)
	self.popup:setAlwaysOnTop(true)
	self.popup:setAutoHide(false)
	self.popup:setTransparent(false)

	-- no way to exit this popup
	self.upgradeListener =
		Framework:addListener(EVENT_ALL_INPUT,
				      function()
					      Framework.wakeup()
					      return EVENT_CONSUME
				      end,
				      true)

	-- disconnect from SqueezeCenter, we don't want to up
	-- interrupted during the firmware upgrade.
	appletManager:callService("disconnectPlayer")

	-- stop memory hungry services before upgrading
	if (System:getMachine() == "fab4") then

		appletManager:callService("stopSqueezeCenter")
		appletManager:callService("stopFileSharing")

		-- start the upgrade once SBS is shut down or timed out
		local timeout = 0
		self.serverStopTimer = self.popup:addTimer(1000, function()

			timeout = timeout + 1
			
			if timeout <= STOP_SERVER_TIMEOUT and appletManager:callService("isBuiltInSCRunning") then
				return
			end

			Task("upgrade", self, _doUpgrade, _upgradeFailed):addTask()
			
			self.popup:removeTimer(self.serverStopTimer)
		end)
	else
		Task("upgrade", self, _doUpgrade, _upgradeFailed):addTask()
	end

	self:tieAndShowWindow(self.popup)
	return window
end


function _doUpgrade(self)
	Task:yield(true)

	-- EN only messages
	local str = { UPDATE_DOWNLOAD = "Kernel Download", UPDATE_VERIFY = "Kernel Verify", UPDATE_REBOOT = "Restarting" }

	local t, err = KernelUpgrade():start(self.url, self.md5, 
		function (done, msg, count)
			if type(count) == "number" then
				if count >= 100 then
					count = 100
				end
				self.counter:setValue(count .. "%")
				self.progress:setRange(1, 100, count)
			else
				self.counter:setValue("")
			end
			
			self.text:setValue(str[msg] or msg)
			
			if done then
				self.icon:setStyle("icon_restart")
			end
		end
	)
	if not t then
		log:error("Upgrade failed: ", err)
		self:_upgradeFailed()

		if self.popup then
			self.popup:hide()
			self.popup = nil
		end
	end
end


function _upgradeFailed(self)
	-- unblock keys
	Framework:removeListener(self.upgradeListener)
	self.upgradeListener = nil

	-- reconnect to server
	appletManager:callService("connectPlayer")

	local window = Window("help_list", "Kernel Update Failed")
	local menu = SimpleMenu("menu")
	window:addWidget(menu)

	menu:addItem({
		text = "Cancel",
		sound = "WINDOWHIDE",
		callback = function()
					   window:hide()
				   end,
	})

	self:tieAndShowWindow(window)
end
