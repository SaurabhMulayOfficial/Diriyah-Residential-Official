import { LightningElement } from 'lwc';

import PRODUCT_HOLD_TITLE from '@salesforce/label/c.RES_ProductSoftHoldTitle';
import PRODUCT_HOLD_MESSAGE from '@salesforce/label/c.RES_ProductSoftHoldMessage';

export default class ProductSoftHoldBanner extends LightningElement {

    labels = {
        PRODUCT_HOLD_TITLE,
        PRODUCT_HOLD_MESSAGE
    };

}