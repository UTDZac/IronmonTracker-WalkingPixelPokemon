local function WalkingPixelPokemon()
	local self = {
		version = "2.0",
		name = "Walking Pixel Pokémon",
		author = "Eiphzor",
		description = "Replaces the Animated " .. Constants.Words.POKEMON .. " Pop-out sprites with walking pixel variants from HGSS.",
		github = "UTDZac/IronmonTracker-WalkingPixelPokemon",
		requiredVersion = "v8.5.0", -- minimum Tracker version required to use this extension with full support
	}
	self.url = string.format("https://github.com/%s", self.github or "")

	self.IconFolders = {
		Original = "WalkingPokemonIcons",
		BW = "WalkingPokemonIconsBW", -- Currently unused
	}

	-- These variables are setup later in `startup()`; examples are shown
	self.chosenFolder = nil -- e.g. "WalkingPokemonIcons"
	self.extensionIconFolder = nil -- e.g. "MY_TRACKER_FOLDER/extensions/WalkingPokemonIcons/"
	self.fullIconPathFormat = nil -- e.g. "MY_TRACKER_FOLDER/extensions/WalkingPokemonIcons/%s.gif"

	self.EXTENSION_KEY = "WalkingPixelPokemon"
	self.SETTINGS_KEY = "WalkingPixelPokemon"
	self.Settings = {
		["CustomFolder"] = {}, -- If provided in options, will use this folder instead of the original
	}
	-- Define save/load settings functions
	for key, setting in pairs(self.Settings or {}) do
		setting.key = tostring(key)
		if type(setting.load) ~= "function" then
			setting.load = function(this)
				local loadedValue = TrackerAPI.getExtensionSetting(self.SETTINGS_KEY, this.key)
				if loadedValue ~= nil then
					this.values = Utils.split(loadedValue, ",", true)
				end
				return this.values
			end
		end
		if type(setting.save) ~= "function" then
			setting.save = function(this)
				if this.values ~= nil then
					local savedValue = table.concat(this.values, ",") or ""
					TrackerAPI.saveExtensionSetting(self.SETTINGS_KEY, this.key, savedValue)
				end
			end
		end
		if type(setting.get) ~= "function" then
			setting.get = function(this)
				if this.values ~= nil and #this.values > 0 then
					return table.concat(this.values, ",")
				else
					return nil
				end
			end
		end
	end

	function self.verifyIconFolderExists()
		if not FileManager.folderExists(self.extensionIconFolder) then
			print(string.format("[%s] Can't find custom folder, using original folder instead.\n> %s", self.SETTINGS_KEY, self.extensionIconFolder))
			self.setIconFolder(self.IconFolders.Original)
		end

	end

	function self.loadSettings()
		for _, setting in pairs(self.Settings or {}) do
			setting:load()
		end

		local customFolder = self.Settings["CustomFolder"]:get()
		if not Utils.isNilOrEmpty(customFolder) then
			self.setIconFolder(customFolder)
			self.verifyIconFolderExists()
		end
	end

	function self.setIconFolder(folderName)
		self.chosenFolder = folderName

		local pathParts = {
			FileManager.getCustomFolderPath(),
			self.chosenFolder,
			FileManager.slash,
		}
		self.extensionIconFolder = table.concat(pathParts)
		self.fullIconPathFormat = self.extensionIconFolder .. "%s" .. FileManager.Extensions.ANIMATED_POKEMON
	end

	function self.setupImagePathOverrides()
		Drawing.ImagePaths.AnimatedPokemon.getOverridePath = function(this, value)
			-- value: the pokemon name, all lowercase
			if value then
				return string.format(self.fullIconPathFormat, value)
			else
				return nil
			end
		end
	end

	function self.removeImagePathOverrides()
		Drawing.ImagePaths.AnimatedPokemon.getOverridePath = nil
	end

	function self.hardRefreshViewedPokemon()
		if not Options["Animated Pokemon popout"] then
			return
		end
		local leadPokemon = Tracker.getPokemon(Battle.Combatants.LeftOwn, true) or Tracker.getDefaultPokemon()
		if not PokemonData.isValid(leadPokemon.pokemonID) or not Program.isValidMapLocation() then
			return
		end
		-- Force change the viewed animated Pokemon
		Drawing.AnimatedPokemon.pokemonID = 0
		Drawing.AnimatedPokemon:setPokemon(leadPokemon.pokemonID)
	end

	function self.openOptionsPopup()
		if not Main.IsOnBizhawk() then return end

		local form = Utils.createBizhawkForm(string.format("%s Options", self.SETTINGS_KEY), 320, 130, 100, 20)
		local leftX = 18
		local boxH = 20
		local nextLineY = 12

		local customFolder = self.Settings["CustomFolder"]:get()
		if Utils.isNilOrEmpty(customFolder) then
			customFolder = self.IconFolders.Original
		end

		-- Options
		forms.label(form, "Icons folder name (in your Tracker's extensions folder):", leftX, nextLineY, 300, boxH)
		nextLineY = nextLineY + 25
		local textboxCustomFolder = forms.textbox(form, customFolder, 200, boxH, nil, leftX + 21, nextLineY - 2)
		nextLineY = nextLineY + 25

		-- Buttons
		nextLineY = nextLineY + 5
		forms.button(form, Resources.AllScreens.Save, function()
			local customFolderText = forms.gettext(textboxCustomFolder) or ""
			self.Settings["CustomFolder"].values = { customFolderText }
			self.Settings["CustomFolder"]:save()

			-- Try to use the custom folder, if it exists
			self.setIconFolder(customFolderText)
			self.verifyIconFolderExists()
			self.hardRefreshViewedPokemon()

			Utils.closeBizhawkForm(form)
		end, 30, nextLineY)
		forms.button(form, "(Default)", function()
			forms.settext(textboxCustomFolder, self.IconFolders.Original)
		end, 121, nextLineY)
		forms.button(form, Resources.AllScreens.Cancel, function()
			Utils.closeBizhawkForm(form)
		end, 212, nextLineY)
	end

	-- Executed only once: when the Tracker finishes starting up and after it loads all other required files and code
	function self.startup()
		self.originalAnimatedOption = nil

		if not Drawing.ImagePaths then
			-- Pop up a delayed warning to notify that the current tracker needs updating to use this extension
			-- Also disable this extension to prevent future warnings
			Program.addFrameCounter("WalkingPixelPokemonExtWarning", 5, function()
				local warningMessage = string.format("The WalkingPixelPokemon extension requires Tracker %s or higher.\n\nPlease update your Tracker before using this extension.", self.requiredVersion)
				Main.DisplayError(warningMessage, "Update", function()
					Program.changeScreenView(UpdateScreen)
					if Main.IsOnBizhawk() then client.unpause() end
				end)
				CustomCode.disableExtension(self.EXTENSION_KEY)
			end, 1)
			return
		end

		-- Force this feature to be enabled but it redirects to using the walking pixel icons
		self.originalAnimatedOption = (Options["Animated Pokemon popout"] == true)
		Options["Animated Pokemon popout"] = true

		self.setIconFolder(self.IconFolders.Original)
		self.loadSettings()
		self.setupImagePathOverrides()
		self.hardRefreshViewedPokemon()
	end

	-- Executed only once: when the extension is disabled by the user, necessary to undo any customizations, if able
	function self.unload()
		-- Restores the original setting
		if self.originalAnimatedOption ~= nil then
			Options["Animated Pokemon popout"] = (self.originalAnimatedOption == true)
		end

		self.removeImagePathOverrides()
		self.hardRefreshViewedPokemon()
	end

	-- Executed when the user clicks the "Check for Updates" button while viewing the extension details within the Tracker's UI
	function self.checkForUpdates()
		local versionResponsePattern = '"tag_name":%s+"%w+(%d+%.%d+%.%d+%.?%d*)"' -- matches "1.0" in "tag_name": "v1.0"
		local versionCheckUrl = string.format("https://api.github.com/repos/%s/releases/latest", self.github or "")
		local downloadUrl = string.format("%s/releases/latest", self.url or "")
		local compareFunc = function(a, b) return a ~= b and not Utils.isNewerVersion(a, b) end -- if current version is *older* than online version
		local isUpdateAvailable = Utils.checkForVersionUpdate(versionCheckUrl, self.version, versionResponsePattern, compareFunc)
		return isUpdateAvailable, downloadUrl
	end

	-- Executed when the user clicks the "Options" button while viewing the extension details within the Tracker's UI
	function self.configureOptions()
		self.openOptionsPopup()
	end

	return self
end
return WalkingPixelPokemon