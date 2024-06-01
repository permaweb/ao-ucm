PIXL_PROCESS = '8Lz_BvNqxlhSlyx282o4v7AIwKQpUn-qklhDnHgUWQs'

Handlers.add('Cron', Handlers.utils.hasMatchingTag('Action', 'Cron'),
	function(msg)
		ao.send({ Target = PIXL_PROCESS, Tags = { Action = 'Run-Rewards' } })
	end
)
