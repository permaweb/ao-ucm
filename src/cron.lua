PIXL_PROCESS = 'DM3FoZUq_yebASPhgd8pEIRIzDW6muXEhxz5-JwbZwo'

Handlers.add('Cron', Handlers.utils.hasMatchingTag('Action', 'Cron'),
	function(msg)
		ao.send({ Target = PIXL_PROCESS, Tags = { Action = 'Run-Rewards' } })
	end
)
