import { LightningElement, api, track } from 'lwc';
import { NavigationMixin }              from 'lightning/navigation';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getConvertedRecordIds from '@salesforce/apex/RES_LeadConversionHandler.getConvertedRecordIds';
import USER_ID from '@salesforce/user/Id';
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
    @track accountType      = '';
    @track accountPhone     = '';
    @track accountWebsite   = '';
    @track accountOwnerName = '';
    @track accountSite      = '';

    @track contactName   = '';
    @track contactTitle  = '';
    @track contactPhone  = '';
    @track contactEmail  = '';
    @track contactMobile = '';

    @track opportunityName      = '';
    @track opportunityCloseDate = '';
    @track opportunityAmount    = '';
    @track opportunityOwnerName = '';

    _subscription   = {};
    _isProcessing   = false; // ✅ Guard against duplicate CDC events
    CDC_CHANNEL     = '/data/LeadChangeEvent';

    async connectedCallback() {
        this._subscribeToChannel();
        this._registerErrorHandler();
    }

    disconnectedCallback() {
        this._unsubscribeFromChannel();
    }

    _subscribeToChannel() {
        subscribe(this.CDC_CHANNEL, -1, (response) => {
            this._processChangeEvent(response);
        }).then((response) => {
            this._subscription = response;
            console.log('✅ Subscribed to CDC:', response.channel);
        });
    }

    async _processChangeEvent(response) {
        const header  = response?.data?.payload?.ChangeEventHeader;
        const payload = response?.data?.payload;
        if (!header) return;

        const { changeType, recordIds, entityName, changedFields } = header;

        console.log('CDC Event | Entity:', entityName,
                    '| Type:', changeType,
                    '| Fields:', changedFields,
                    '| IsConverted:', payload?.IsConverted);

        if (entityName !== 'Lead' || changeType !== 'UPDATE') return;

        if (!recordIds.includes(this.recordId)) return;
        if (!changedFields.includes('IsConverted')) return;
        if (payload.IsConverted !== true)           return;

        if (this._isProcessing) {
            console.warn('Already processing — skipping duplicate CDC event');
            return;
        }

        this._isProcessing = true;
        this.isLoading     = true;

        await this._delay(3000);
        await this._fetchConvertedIds(0);
    }

    // ─── Fetch Converted Record Details ──────────────────────────
    async _fetchConvertedIds(retryCount = 0) {
        try {
            const result = await getConvertedRecordIds({ leadId: this.recordId });
            const convertedByUser = result?.LastModifiedById;
            if (convertedByUser !== USER_ID) {
                this.showPopup = false;
                this.isLoading = false;
                this._isProcessing = false;

                return;
            }
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
            this.accountType      = result.accountType      || '';
            this.accountPhone     = result.accountPhone     || '';
            this.accountWebsite   = result.accountWebsite   || '';
            this.accountOwnerName = result.accountOwnerName || '';
            this.accountSite      = result.accountSite      || '';

            this.contactName   = result.contactName   || '';
            this.contactTitle  = result.contactTitle  || '';
            this.contactPhone  = result.contactPhone  || '';
            this.contactEmail  = result.contactEmail  || '';
            this.contactMobile = result.contactMobile || '';

            this.opportunityName      = result.opportunityName      || '';
            this.opportunityCloseDate = result.opportunityCloseDate || '';
            this.opportunityAmount    = result.opportunityAmount    || '';
            this.opportunityOwnerName = result.opportunityOwnerName || '';

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
        this.accountType      = '';
        this.accountPhone     = '';
        this.accountWebsite   = '';
        this.accountOwnerName = '';
        this.accountSite      = '';
        this.contactName      = '';
        this.contactTitle     = '';
        this.contactPhone     = '';
        this.contactEmail     = '';
        this.contactMobile    = '';
        this.opportunityName      = '';
        this.opportunityCloseDate = '';
        this.opportunityAmount    = '';
        this.opportunityOwnerName = '';
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
        onError((error) => console.error('EmpApi Error:', error));
    }
}