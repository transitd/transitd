/*

transitd web UI sessions js file

@license The MIT License (MIT)
@author Alex <alex@maximum.guru>
@author Serg <sklassen410@gmail.com>
@copyright 2016 Alex
@copyright 2016 Serg

*/

var activeSessions = [];

function clearSessionList() {
	$("#sessions tbody").empty();
}

function insertSession(sid, name, meshIP, port, suite, internetIPv4, internetIPv6, timeoutTimestamp)
{
	var sRow = $( "<tr>"
				+"<td class='name'></td>"
				+"<td class='meshIP'></td>"
				+"<td class='port'></td>"
				+"<td class='suite'></td>"
				+"<td class='internetIPv4'></td>"
				+"<td class='internetIPv6'></td>"
				+"<td class='timeoutTimestamp'></td>"
				+"<td><button class='disconnect btn btn-primary' id='disconnect'>Disconnect</button></td>"
				+"</tr>");
	sRow.find(".name").text(name);
	sRow.find(".meshIP").text(meshIP);
	sRow.find(".port").text(port);
	sRow.find(".suite").text(suite);
	sRow.find(".internetIPv4").text(internetIPv4);
	sRow.find(".internetIPv6").text(internetIPv6);
	sRow.find(".timeoutTimestamp").text((new Date(timeoutTimestamp*1000)).toString());
	sRow.find(".disconnect").click(function(e) {
		e.preventDefault();
		disconnect(sid);
	});
 
	$("#sessions tbody").append(sRow);
}

var sessionsTimeout;

function reloadSessions()
{
	if(sessionsTimeout)
		clearTimeout(sessionsTimeout);
	service.listSessions({
		params: [],
		onSuccess: function(result) {
			nonBlockingCallWrapper(result, function(result) {
				clearSessionList();
				sessionsTimeout = setTimeout(reloadSessions,5000);
				if(result.success==true)
				{
					var activeSessions = result.sessions;
					if(activeSessions == undefined || activeSessions.length == undefined || activeSessions.length==0)
						$('#sessions').hide();
					else
						$('#sessions').show();
					if(activeSessions)
						for (index = 0; index < activeSessions.length; ++index)
						{
							var activeSession = activeSessions[index];
							insertSession(activeSession.sid,
										  activeSession.name,
										  activeSession.meshIP,
										  activeSession.port,
										  activeSession.suite,
										  activeSession.internetIPv4,
										  activeSession.internetIPv6,
										  activeSession.timeoutTimestamp);
						}
				}
				else
				{
					sessionsTimeout = setTimeout(reloadSessions,5000);
					logAppendMessage('danger', result.errorMsg);
				}
			});
		},
		onException: function(e) {
			logAppendMessage('danger', e);
			sessionsTimeout = setTimeout(reloadSessions,5000);
			return true;
		}
	});	
}
