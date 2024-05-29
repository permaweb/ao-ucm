PIXL_PROCESS = 'jmu9__Fw79vcsCbPD15cy-xR0zFZa3lXv16rbpWQtRA'

Handlers.add('Cron', Handlers.utils.hasMatchingTag('Action', 'Cron'),
	function(msg)
		ao.send({ Target = PIXL_PROCESS, Tags = { Action = 'Run-Rewards' } })
	end
)
