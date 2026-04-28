({
    doInit: function(component, event, helper) {
        // Extract recordTypeId from URL (set by SF after standard RT selection page)
        var rtId = '';

        try {
            var pageRef = component.get('v.pageReference');
            if (pageRef && pageRef.state) {
                rtId = pageRef.state.recordTypeId || pageRef.state.RecordTypeId || '';
            }
        } catch(e) {}

        if (!rtId) {
            try {
                var m = (window.location.search + window.location.hash)
                            .match(/[?&#]recordTypeId=([a-zA-Z0-9]{15,18})/i);
                if (m) rtId = m[1];
            } catch(e) {}
        }

        if (!rtId) {
            try {
                var m2 = window.location.href.match(/recordTypeId=([a-zA-Z0-9]{15,18})/i);
                if (m2) rtId = m2[1];
            } catch(e) {}
        }

        // Use Apex to get developer name and display name from the RT Id
        if (rtId) {
            var action = component.get('c.getRecordTypeById');
            action.setParams({ recordTypeId: rtId });
            action.setCallback(this, function(response) {
                var rtDevName = '';
                var rtName    = '';
                if (response.getState() === 'SUCCESS') {
                    var rt = response.getReturnValue();
                    if (rt) {
                        rtDevName = rt.developerName || '';
                        rtName    = rt.name          || '';
                    }
                }
                // Invoke LWC with retry — LWC's own @wire(CurrentPageReference) 
                // also fires independently, so this acts as a reliable backup trigger
                var attempts = 0;
                function tryInvoke() {
                    if (!component.isValid()) return;
                    var modal = component.find('lwcModal');
                    if (modal && typeof modal.invoke === 'function') {
                        modal.invoke(rtId, rtDevName, rtName);
                    } else if (attempts < 30) {
                        attempts++;
                        window.setTimeout($A.getCallback(tryInvoke), 100);
                    }
                }
                tryInvoke();
            });
            $A.enqueueAction(action);
        } else {
            // No RT id - still try to nudge the LWC open
            var attempts = 0;
            function tryInvokeEmpty() {
                if (!component.isValid()) return;
                var modal = component.find('lwcModal');
                if (modal && typeof modal.invoke === 'function') {
                    modal.invoke('', '', '');
                } else if (attempts < 30) {
                    attempts++;
                    window.setTimeout($A.getCallback(tryInvokeEmpty), 100);
                }
            }
            tryInvokeEmpty();
        }
    }
})