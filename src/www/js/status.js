var statusTimeout;

function reloadStatus()
{
	if(statusTimeout)
		clearTimeout(statusTimeout);
	service.status({
		params: [],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				statusTimeout = setTimeout(reloadStatus,5000);
				if(result.success==true)
				{
					var html = '';
					if(result.online)
						 html += '<span class="glyphicon glyphicon-globe text-success" aria-hidden="true"></span> ';
					else
						 html += '<span class="glyphicon glyphicon-remove-sign text-danger" aria-hidden="true"></span> ';
					if(result.ipv4)
						html += result.ipv4.ip + "/" + result.ipv4.cidr + ' ';
					if(result.ipv6)
						html += result.ipv6.ip + "/" + result.ipv6.cidr + ' ';
					$("#status").html(html);
				}
				else
				{
					statusTimeout = setTimeout(reloadStatus,5000);
					logAppendMessage('danger', result.errorMsg);
				}
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			statusTimeout = setTimeout(reloadStatus,5000);
			return true;
		}
	});
}
