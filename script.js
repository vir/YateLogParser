
function on_click_log_message(head)
{
	var e = head.parentNode;
	var pos = e.className.indexOf("collapsed");
	if(pos < 0) {
		e.className = 'collapsed ' + e.className;
	} else {
		e.className = e.className.substring(0, pos) + e.className.substring(pos + 10);
	}
}


