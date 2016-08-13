
function startScan()
{
	service.startScan({
		params: [],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				if(result.success==true)
					logAppendMessage('success', "Started scan "+result.scanId);
				else
					logAppendMessage('danger', result.errorMsg);
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			return true;
		}
	});
}
