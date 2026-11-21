return {
	-- Controller version is managed by the installer.

	-- UI refresh interval (seconds)
	REFRESH_INTERVAL = 0.05,

	-- Wireless modem mode (true = receive data wirelessly, false = direct cable)
	IS_WIRELESS = false,
	-- Modem channel used for wireless communication
	MODEM_CHANNEL = 42,

	-- Safety checks (true = enabled, false = disabled)
	SAFETY_COOLANT_ENABLED = true,
	SAFETY_DAMAGE_ENABLED = true,
	SAFETY_HEATED_ENABLED = true,
	SAFETY_WASTE_ENABLED = true,
}
