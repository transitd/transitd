/*

transitd configuration web UI js file

@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@copyright 2016 Alex

*/

function initConfiguration(config)
{
	$('input[name=main\\.name]').val(config.main.name);
	
	$('input[name=gateway\\.enabled][geval=yes]').prop("checked", config.gateway.enabled=="yes");
	$('input[name=gateway\\.enabled][geval=no]').prop("checked", config.gateway.enabled!="yes");
	
	$('#onepage-config form button[type=submit]').click(function(e){
		e.preventDefault();
		configure({
			'main.name': $('input[name=main\\.name]').val(),
			'gateway.enabled': $('input[name=gateway\\.enabled][geval=yes]').is(':checked') ? 'yes' : 'no',
		});
		$(this).addClass('hidden');
	});
}

function configure(settings)
{
	service.configure({
		params: [settings],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				if(result.success==true)
				{
					logAppendMessage('danger', "Restarting...");
					restarting = true;
					setInterval(function(){ window.location.href = window.location.href; }, 15000);
				}
				else
				{
					logAppendMessage('danger', result.errorMsg);
				}
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			return true;
		}
	});
}