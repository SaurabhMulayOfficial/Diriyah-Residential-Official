import { LightningElement, api, track, wire } from 'lwc';
import { NavigationMixin }              from 'lightning/navigation';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import { getRecord, getFieldValue, updateRecord } from 'lightning/uiRecordApi';
import ID_FIELD from '@salesforce/schema/Lead.Id';
import getConvertedRecordIds from '@salesforce/apex/RES_LeadConversionHandler.getConvertedRecordIds';
import triggerLeadConversion from '@salesforce/apex/RES_LeadConversionHandler.triggerLeadConversion';
import USER_ID from '@salesforce/user/Id';
import SUB_STATUS_FIELD from '@salesforce/schema/Lead.RES_Lead_Sub_Status__c';
import STATUS_FIELD     from '@salesforce/schema/Lead.Status';
import OWNER_FIELD      from '@salesforce/schema/Lead.OwnerId';
export default class LeadConversionPopup extends NavigationMixin(LightningElement) {
    @api recordId;
    @track showPopup      = false;
    @track isLoading      = false;
    @track errorMessage   = '';
    @track isPersonAccount = false;

    @track convertedAccountId     = null;
    @track convertedContactId     = null;
    @track convertedOpportunityId = null;

    @track accountName      = '';
    @track accountPhone     = '';
    @track accountWebsite   = '';
    @track accountOwnerName = '';
    @track accountSource = '';
    @track accountRating = '';
    @track accountMobile = '';
    @track accountEmail  = '';

    @track contactName   = '';
    @track contactEmail  = '';
    @track contactMobile = '';
    @track contactLeadSource = '';

    @track opportunityName      = '';
    @track opportunityCloseDate = '';
    @track opportunityOwnerName = '';
    @track opportunityProject    = '';
    @track opportunityLeadSource = '';

    // ── Warning modal state ──────────────────────────────────────
    @track showWarningModal = false;
    @track _proceedError    = '';
    _previousSubStatus      = '';
    _currentSubStatus         = '';
    _previousStatus           = '';
    _currentStatus            = '';
    _isFirstLoad              = true;
    _isReverting              = false;
    _isProceedSave            = false;

    _subscription   = {};
    _isProcessing   = false;
    EVENT_CHANNEL = '/event/RES_Lead_Conversion_Event__e';

    // ── Wire: watch Sub-Status + Status — show warning on Qualified ──
    _ownerId = '';

    @wire(getRecord, { recordId: '$recordId', fields: [SUB_STATUS_FIELD, STATUS_FIELD, OWNER_FIELD] })
    wiredLead({ data }) {
        if (!data) return;
        const subStatus = getFieldValue(data, SUB_STATUS_FIELD) || '';
        const status    = getFieldValue(data, STATUS_FIELD)     || '';
        this._ownerId   = getFieldValue(data, OWNER_FIELD)      || '';

        if (this._isFirstLoad) {
            this._previousSubStatus = subStatus;
            this._currentSubStatus  = subStatus;
            this._previousStatus    = status;
            this._currentStatus     = status;
            this._isFirstLoad       = false;
            return;
        }

        // Skip reactions caused by our own Proceed/Cancel updateRecord calls
        if (this._isReverting || this._isProceedSave) {
            this._previousSubStatus = subStatus;
            this._currentSubStatus  = subStatus;
            this._previousStatus    = status;
            this._currentStatus     = status;
            this._isReverting       = false;
            this._isProceedSave     = false;
            return;
        }

        const changedToQualified =
            subStatus === 'Qualified' &&
            this._currentSubStatus !== 'Qualified';

        if (changedToQualified) {
            // Keep _previous* intact for revert; update _current* to new values
            this._currentSubStatus = subStatus;
            this._currentStatus    = status;
            this._savePendingRevert(this._previousSubStatus, this._previousStatus);
            this.showWarningModal  = true;
        } else if (subStatus !== this._currentSubStatus || status !== this._currentStatus) {
            // Unrelated field change — update all tracking
            this._previousSubStatus = subStatus;
            this._currentSubStatus  = subStatus;
            this._previousStatus    = status;
            this._currentStatus     = status;
        }
    }

    async connectedCallback() {
        this._checkAndApplyPendingRevert();
        this._subscribeToChannel();
        this._registerErrorHandler();
    }

    disconnectedCallback() {
        this._unsubscribeFromChannel();
    }

    _subscribeToChannel() {
        subscribe(this.EVENT_CHANNEL, -1, (response) => {
            this._processPlatformEvent(response);
        }).then((response) => {
            this._subscription = response;
            console.log('✅ Subscribed to Platform Event:', response.channel);
        });
    }

        async _processPlatformEvent(response) {
            const payload = response?.data?.payload;
            if (!payload) {
                return;
            }
            if (payload.Lead_Id__c !== this.recordId) {
                return;
            }
            if (payload.Converted_By__c !== USER_ID) {
                return;
            }
            if (this._isProcessing) {
                return;
            }
            this._isProcessing = true;
            this.isLoading = true;
            await this._delay(2000);
            await this._fetchConvertedIds();
        }

    // ─── Fetch Converted Record Details ──────────────────────────
    async _fetchConvertedIds(retryCount = 0) {
        try {
            const result = await getConvertedRecordIds({ leadId: this.recordId });
                this.showPopup = true;
            const isEmpty = !result || Object.keys(result).length === 0 || !result.accountId;

            if (isEmpty) {
                if (retryCount < 4) {
                    console.warn(`Empty result — retry ${retryCount + 1} of 4 in 2s`);
                    await this._delay(2000);
                    return await this._fetchConvertedIds(retryCount + 1);
                }
                this.errorMessage  = 'Could not load converted records. Please refresh.';
                this.isLoading     = false;
                this._isProcessing = false;
                return;
            }

            this.isPersonAccount        = result.isPersonAccount === 'true';
            this.convertedAccountId     = result.accountId     || null;
            this.convertedContactId     = result.contactId     || null;
            this.convertedOpportunityId = result.opportunityId || null;

            this.accountName      = result.accountName      || '';
            this.accountPhone     = result.accountPhone     || '';
            this.accountWebsite   = result.accountWebsite   || '';
            this.accountOwnerName = result.accountOwnerName || '';
            this.accountSource = result.accountSource || '';
            this.accountRating = result.accountRating || '';
            this.accountMobile = result.accountMobile || ''; // Person Account
            this.accountEmail  = result.accountEmail  || '';

            this.contactName   = result.contactName   || '';
            this.contactEmail  = result.contactEmail  || '';
            this.contactMobile = result.contactMobile || '';
            this.contactLeadSource = result.contactLeadSource || '';

            this.opportunityName      = result.opportunityName      || '';
            this.opportunityCloseDate = result.opportunityCloseDate || '';
            this.opportunityOwnerName = result.opportunityOwnerName || '';
            this.opportunityProject    = result.opportunityProject    || '';
            this.opportunityLeadSource = result.opportunityLeadSource || '';

            this.errorMessage  = '';
            this.isLoading     = false;
            this._isProcessing = false;

        } catch (error) {
            console.error('Apex error:', JSON.stringify(error));
            if (retryCount < 4) {
                await this._delay(2000);
                return await this._fetchConvertedIds(retryCount + 1);
            }
            this.errorMessage  = 'Could not load converted records. Please refresh.';
            this.isLoading     = false;
            this._isProcessing = false;
        }
    }

    // ─── Card Click Handlers ──────────────────────────────────────
    handleAccountClick(event) {
        event.stopPropagation();
        this._navigateToRecord(this.convertedAccountId);
    }

    handleContactClick(event) {
        event.stopPropagation();
        this._navigateToRecord(this.convertedContactId);
    }

    handleOpportunityClick(event) {
        event.stopPropagation();
        this._navigateToRecord(this.convertedOpportunityId);
    }

    _navigateToRecord(recordId) {
        if (!recordId) return;
        this[NavigationMixin.Navigate]({
            type      : 'standard__recordPage',
            attributes: { recordId, actionName: 'view' }
        });
        this.closePopup();
    }

    handleGoToLeads(event) {
        event.stopPropagation();
        this[NavigationMixin.Navigate]({
            type      : 'standard__objectPage',
            attributes: { objectApiName: 'Lead', actionName: 'list' },
            state     : { filterName: 'Recent' }
        });
        this.closePopup();
    }


    // ── Warning modal: Proceed — update Status to '04' and directly enqueue conversion ─
    handleProceed() {
        this._proceedError = '';
        this._clearPendingRevert();
        if (this._ownerId && !this._ownerId.startsWith('005')) {
            this._proceedError = 'This lead is assigned to a Queue. Please reassign it to a User before converting.';
            return;
        }
        this.showWarningModal = false;
        this._isProceedSave   = true;
        updateRecord({
            fields: {
                [ID_FIELD.fieldApiName]         : this.recordId,
                [STATUS_FIELD.fieldApiName]     : '04',
                [SUB_STATUS_FIELD.fieldApiName] : 'Qualified'
            }
        }).then(() => {
            this._previousSubStatus = 'Qualified';
            this._previousStatus    = '04';
            return triggerLeadConversion({ leadId: this.recordId });
        }).catch(error => {
            this._isProceedSave  = false;
            this._proceedError   = this._extractErrorMessage(error);
            this.showWarningModal = true;
        });
    }

    // ── Warning modal: Cancel/X — close immediately, revert in background ──
    handleCancelWarning() {
        this.showWarningModal = false;
        this._proceedError    = '';
        this._clearPendingRevert();
        this._isReverting     = true;
        updateRecord({
            fields: {
                [ID_FIELD.fieldApiName]         : this.recordId,
                [SUB_STATUS_FIELD.fieldApiName] : this._previousSubStatus || null,
                [STATUS_FIELD.fieldApiName]     : this._previousStatus    || null
            }
        }).catch(error => {
            this._isReverting = false;
            console.error('Error reverting fields:', JSON.stringify(error));
        });
    }

    _extractErrorMessage(error) {
        const messages = [];
        const output = error?.body?.output;
        if (output?.errors?.length) {
            output.errors.forEach(e => { if (e.message) messages.push(e.message); });
        }
        if (output?.fieldErrors) {
            Object.values(output.fieldErrors).forEach(fieldErrs => {
                fieldErrs.forEach(e => { if (e.message) messages.push(e.message); });
            });
        }
        if (!messages.length && error?.body?.message) {
            messages.push(error.body.message);
        }
        return messages.join(' ') || 'An error occurred. Please check required fields and try again.';
    }

    closePopup() {
        this.showPopup              = false;
        this.isLoading              = false;
        this.isPersonAccount        = false;
        this.errorMessage           = '';
        this._isProcessing          = false;
        this.convertedAccountId     = null;
        this.convertedContactId     = null;
        this.convertedOpportunityId = null;
        this.accountName      = '';
        this.accountPhone     = '';
        this.accountWebsite   = '';
        this.accountOwnerName = '';
        this.contactName      = '';
        this.contactEmail     = '';
        this.contactMobile    = '';
        this.opportunityName      = '';
        this.opportunityCloseDate = '';
        this.opportunityOwnerName = '';
        this.accountSource       = '';
        this.accountRating       = '';
        this.accountMobile       = '';
        this.accountEmail        = '';
        this.opportunityProject  = '';
        this.opportunityLeadSource = '';
    }

    get hasAccount()     { return !!this.convertedAccountId; }
    get hasContact()     { return !!this.convertedContactId; }
    get hasOpportunity() { return !!this.convertedOpportunityId; }

    get accountTileLabel() {
        return this.isPersonAccount ? 'PERSON ACCOUNT' : 'ACCOUNT';
    }
    get accountCardClass() {
        return `record-card${this.hasAccount ? ' clickable' : ' disabled'}`;
    }
    get contactCardClass() {
        return `record-card${this.hasContact ? ' clickable' : ' disabled'}`;
    }
    get opportunityCardClass() {
        return `record-card${this.hasOpportunity ? ' clickable' : ' disabled'}`;
    }

    // ── Pending-revert helpers: survive page refresh AND tab close via localStorage ──
    // TTL of 2 hours — prevents a stale entry from reverting a record opened much later.
    static REVERT_TTL_MS = 2 * 60 * 60 * 1000;

    get _revertKey() {
        return `res_lead_pending_revert_${this.recordId}`;
    }

    _savePendingRevert(prevSubStatus, prevStatus) {
        try {
            localStorage.setItem(this._revertKey, JSON.stringify({
                subStatus : prevSubStatus,
                status    : prevStatus,
                savedAt   : new Date().getTime()
            }));
        } catch (e) { /* storage unavailable */ }
    }

    _clearPendingRevert() {
        try { localStorage.removeItem(this._revertKey); } catch (e) { /* ignore */ }
    }

    _checkAndApplyPendingRevert() {
        if (!this.recordId) return;
        let stored;
        try { stored = localStorage.getItem(this._revertKey); } catch (e) { return; }
        if (!stored) return;
        this._clearPendingRevert();
        let parsed;
        try { parsed = JSON.parse(stored); } catch (e) { return; }
        const age = new Date().getTime() - (parsed.savedAt || 0);
        if (age > LeadConversionPopup.REVERT_TTL_MS) return;
        this._isReverting = true;
        updateRecord({
            fields: {
                [ID_FIELD.fieldApiName]         : this.recordId,
                [SUB_STATUS_FIELD.fieldApiName] : parsed.subStatus || null,
                [STATUS_FIELD.fieldApiName]     : parsed.status    || null
            }
        }).catch(error => {
            this._isReverting = false;
            console.error('Error reverting fields after tab close/refresh:', JSON.stringify(error));
        });
    }

    _delay(ms) {
        return new Promise(resolve => {
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            setTimeout(resolve, ms);
        });
    }

    _unsubscribeFromChannel() {
        unsubscribe(this._subscription, () => {
        });
    }

    _registerErrorHandler() {
        onError((error) => {
            if (error?.error !== '403::Unknown client') {
                console.error('EmpApi Error:', error);
            }
        });
    }
}