/*

transitd web UI connection js file

@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@author Serg <sklassen410@gmail.com>
@copyright 2016 Alex
@copyright 2016 Serg

*/

function connectTo(ip, port, method, successCallback, failureCallback)
{
	service.connectTo({
		params: [ip, port, method],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				if(result.success==true)
				{
					var message = "Connected!\n";
					if(result.ipv4)
						message += "IPv4: "+result.ipv4+"\n";
					if(result.ipv6)
						message += "IPv6: "+result.ipv6+"\n";
					message += "Timeout: "+result.timeout+"\n";
					logAppendMessage('success', message);
					if(successCallback)
						successCallback();
					reloadSessions();
					reloadStatus();
				}
				else
				{
					logAppendMessage('danger', result.errorMsg);
					if(failureCallback)
						failureCallback();
				}
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			return true;
		}
	});
}

function disconnect(sid, successCallback, failureCallback)
{
	service.disconnect({
		params: [sid],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				if(result.success==true)
				{
					var message = "Disconnected!";
					logAppendMessage('success', message);
					if(successCallback)
						successCallback();
					reloadSessions();
					reloadStatus();
				}
				else
				{
					logAppendMessage('danger', result.errorMsg);
					if(failureCallback)
						failureCallback();
				}
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			return true;
		}
	});
}
