//
//  MYCSendViewController.m
//  Mycelium Wallet
//
//  Created by Oleg Andreev on 01.10.2014.
//  Copyright (c) 2014 Mycelium. All rights reserved.
//

#import "MYCSendViewController.h"
#import "MYCWallet.h"
#import "MYCWalletAccount.h"
#import "MYCTextFieldLiveFormatter.h"
#import "MYCErrorAnimation.h"
#import "MYCScannerView.h"
#import "MYCUnspentOutput.h"

#if 0 && DEBUG
#warning DEBUG: Zero fees
static BTCSatoshi MYCFeeRate = 0;
#else
static BTCSatoshi MYCFeeRate = 10000;
#endif

@interface MYCSendViewController () <UITextFieldDelegate, BTCTransactionBuilderDataSource>

@property(nonatomic,readonly) MYCWallet* wallet;

@property(nonatomic) BTCSatoshi spendingAmount;
@property(nonatomic) BTCAddress* spendingAddress;

@property(nonatomic) BOOL addressValid;
@property(nonatomic) BOOL amountValid;

@property (weak, nonatomic) IBOutlet UILabel *accountNameLabel;
@property (weak, nonatomic) IBOutlet UIButton *cancelButton;
@property (weak, nonatomic) IBOutlet UIButton *sendButton;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView* spinner;

@property (weak, nonatomic) IBOutlet UITextField *addressField;
@property (weak, nonatomic) IBOutlet UIButton *scanButton;

@property (weak, nonatomic) IBOutlet UIButton *btcButton;
@property (weak, nonatomic) IBOutlet UIButton *fiatButton;

@property (weak, nonatomic) IBOutlet UITextField *btcField;
@property (weak, nonatomic) IBOutlet UITextField *fiatField;

@property (nonatomic) MYCTextFieldLiveFormatter* btcLiveFormatter;
@property (nonatomic) MYCTextFieldLiveFormatter* fiatLiveFormatter;

@property (weak, nonatomic) IBOutlet UILabel *feeLabel;

@property (weak, nonatomic) IBOutlet UIButton *allFundsButton;
@property (weak, nonatomic) IBOutlet UILabel *allFundsLabel;

@property (strong, nonatomic) IBOutletCollection(NSLayoutConstraint)  NSArray*borderHeightConstraints;

@property(weak, nonatomic) MYCScannerView* scannerView;

@property(nonatomic) BOOL fiatInput;

@end

@implementation MYCSendViewController

- (id) initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])
    {
        self.title = NSLocalizedString(@"Send Bitcoins", @"");
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(walletDidUpdateAccount:) name:MYCWalletDidUpdateAccountNotification object:nil];
    }
    return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) viewDidLoad
{
    [super viewDidLoad];

    self.accountNameLabel.text = NSLocalizedString(@"Send", @"");

    [self reloadAccount];

    self.btcLiveFormatter  = [[MYCTextFieldLiveFormatter alloc] initWithTextField:self.btcField numberFormatter:self.wallet.btcFormatterNaked];
    self.fiatLiveFormatter = [[MYCTextFieldLiveFormatter alloc] initWithTextField:self.fiatField numberFormatter:self.wallet.fiatFormatterNaked];

    self.fiatInput = ([MYCWallet currentWallet].preferredCurrency == MYCWalletPreferredCurrencyFiat);

    for (NSLayoutConstraint* c in self.borderHeightConstraints)
    {
        c.constant = 1.0/[UIScreen mainScreen].nativeScale;
    }

    [self.cancelButton setTitle:NSLocalizedString(@"Cancel", @"") forState:UIControlStateNormal];
    [self.sendButton   setTitle:NSLocalizedString(@"Send", @"") forState:UIControlStateNormal];

    self.addressField.placeholder = NSLocalizedString(@"Recipient Address", @"");
    [self.scanButton setTitle:NSLocalizedString(@"Scan Address", @"") forState:UIControlStateNormal];

    [self.allFundsButton setTitle:NSLocalizedString(@"Use all funds", @"") forState:UIControlStateNormal];

    if (self.defaultAddress)
    {
        self.addressField.text = self.defaultAddressLabel ?: self.defaultAddress.base58String;
        self.spendingAddress = self.defaultAddress;
        [self updateAddressView];
    }

    if (self.defaultAmount > 0)
    {
        self.spendingAmount = self.defaultAmount;
        self.btcField.text = [self.wallet.btcFormatterNaked stringFromAmount:self.defaultAmount];
        [self didEditBtc:nil];
    }

    [self updateAmounts];
    [self updateTotalBalance];
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    // Make sure we have the latest unspent outputs.
    if (self.account)
    {
        [self.wallet updateAccount:self.account force:YES completion:^(BOOL success, NSError *error) {

            if (!success)
            {
                // TODO: show error.
            }

            [self reloadAccount];
            [self updateAmounts];
            [self updateAddressView];
            [self updateTotalBalance];
        }];
    }
    else
    {
        [self updateAmounts];
        [self updateAddressView];
        [self updateTotalBalance];
    }

    if (self.prefillAllFunds)
    {
        [self useAllFunds:nil];
    }

    //[self.btcField becomeFirstResponder];
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [[MYCWallet currentWallet] updateExchangeRate:YES completion:^(BOOL success, NSError *error) {
        if (!success && error)
        {
            MYCError(@"MYCSendViewController: Automatic update of exchange rate failed: %@", error);
        }
    }];

    // If last time used QR code scanner, show it this time.
    // Do not show if we have some default address already.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"MYCSendWithScanner"])
    {
        if (!self.defaultAddress)
        {
            [self scan:nil];
        }
    }
}

- (MYCWallet*) wallet
{
    return [MYCWallet currentWallet];
}

- (void) walletDidUpdateAccount:(NSNotification*)notif
{
    if (!self.account) return;

    MYCWalletAccount* wa = notif.object;
    if ([wa isKindOfClass:[MYCWalletAccount class]] && wa.accountIndex == self.account.accountIndex)
    {
        [self reloadAccount];
    }
}

- (void) reloadAccount
{
    if (!_account) return;

    [self.wallet inDatabase:^(FMDatabase *db) {
        [_account reloadFromDatabase:db];
    }];
    self.account = _account;
}

- (void) setAccount:(MYCWalletAccount *)account
{
    _account = account;

    if (self.isViewLoaded && account)
    {
        self.accountNameLabel.text = _account.label;
        [self updateAmounts];
        [self updateTotalBalance];
    }
}

- (void) setSpendingAmount:(BTCSatoshi)spendingAmount
{
    _spendingAmount = spendingAmount;
    [self updateAmounts];
}




#pragma mark - Actions




- (IBAction) cancel:(id)sender
{
    [self.view endEditing:YES];
    [self complete:NO];
}

- (IBAction) send:(id)sender
{
    [self.view endEditing:YES];

    [self updateAddressView];
    [self updateAmounts];

    if (!self.amountValid)
    {
        [MYCErrorAnimation animateError:self.btcField radius:10.0];
        [MYCErrorAnimation animateError:self.btcButton radius:10.0];
        [MYCErrorAnimation animateError:self.fiatField radius:10.0];
        [MYCErrorAnimation animateError:self.fiatButton radius:10.0];
    }

    if (!self.addressValid)
    {
        [MYCErrorAnimation animateError:self.addressField radius:10.0];
        [MYCErrorAnimation animateError:self.scanButton radius:10.0];
    }

    if (self.addressValid && self.amountValid && self.spendingAddress && self.spendingAmount > 0)
    {
        [self updateAccountIfNeeded:^(BOOL success, BOOL updated, NSError *error) {

            // If actually updated account, re-check everything.
            if (updated)
            {
                [self send:sender];
                return;
            }

            if (!success)
            {
                MYCError(@"CANNOT SYNC ACCOUNT BEFORE SENDING: %@", error);
                UIAlertController* ac = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Error", @"")
                                                                            message:NSLocalizedString(@"Can't synchronize the account. Try again later.", @"")
                                                                     preferredStyle:UIAlertControllerStyleAlert];
                [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"")
                                                       style:UIAlertActionStyleCancel
                                                     handler:^(UIAlertAction *action) {}]];
                [self presentViewController:ac animated:YES completion:nil];
            }


            BTCTransactionBuilder* builder = [[BTCTransactionBuilder alloc] init];
            builder.dataSource = self;
            builder.outputs = @[ [[BTCTransactionOutput alloc] initWithValue:self.spendingAmount address:self.spendingAddress] ];
            builder.changeAddress = self.changeAddress ?: self.account.internalAddress;
            builder.feeRate = MYCFeeRate;

            __block NSError* berror = nil;
            __block BTCTransactionBuilderResult* result = nil;

            NSString* authString = [NSString stringWithFormat:NSLocalizedString(@"Authorize spending %@", @""),
                                    [self formatAmountInSelectedCurrency:self.spendingAmount]];

            // Unlock wallet so builder can sign.
            [self.wallet unlockWallet:^(MYCUnlockedWallet *unlockedWallet) {
                result = [builder buildTransaction:&berror];
            } reason:authString];

            if (result && result.unsignedInputsIndexes.count == 0)
            {
                [self.view endEditing:YES];

                MYCLog(@"signed tx: %@", BTCHexStringFromData(result.transaction.data));
                MYCLog(@"signed tx base64: %@", [result.transaction.data base64EncodedStringWithOptions:0]);

                [self beginSpinning];

                UIAlertController* ac = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Confirm payment", @"")
                                                                            message:[NSString stringWithFormat:NSLocalizedString(@"You are sending %@ to %@", @""),
                                                                                     [self formatAmountInSelectedCurrency:self.spendingAmount],
                                                                                     [self.spendingAddress base58String]
                                                                                     ]
                                                                     preferredStyle:UIAlertControllerStyleAlert];
                [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"")
                                                       style:UIAlertActionStyleCancel
                                                     handler:^(UIAlertAction *action) {

                                                         [self endSpinning];

                                                     }]];
                [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Send", @"")
                                                       style:UIAlertActionStyleDefault
                                                     handler:^(UIAlertAction *action) {

                                                        [self broadcastTransaction:result.transaction];

                                                     }]];

                [self presentViewController:ac animated:YES completion:nil];
            }
            else
            {
                MYCLog(@"TX BUILDER ERROR: %@", berror);
                [MYCErrorAnimation animateError:self.view radius:10.0];
            }
        }];
    }
}

- (void) broadcastTransaction:(BTCTransaction*)tx
{
    [self.wallet broadcastTransaction:tx fromAccount:self.account completion:^(BOOL success, BOOL queued, NSError *error) {

        [self endSpinning];

        if (success)
        {
            [self complete:YES];
            return;
        }

        // If failed, but queued, show alert and finish.
        if (queued)
        {
            UIAlertController* ac = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Connection failed", @"")
                                                                        message:NSLocalizedString(@"Your payment can't be completed, please check your internet connection. Your payment will be completed automatically.", @"")
                                                                 preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"")
                                                   style:UIAlertActionStyleCancel
                                                 handler:^(UIAlertAction *action) {
                                                 }]];
            [self presentViewController:ac animated:YES completion:nil];

            [self complete:YES];
            return;
        }

        // Failed and not queued.

        // Force update account so we are up to date.
        if (self.account)
        {
            [self.wallet updateAccount:self.account force:YES completion:^(BOOL success, NSError *error) {
            }];
        }

        // Tell the user that transaction failed and must be re-done.
        UIAlertController* ac = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Payment invalid", @"")
                                                                    message:NSLocalizedString(@"Your payment was rejected. Please try to synchronize your account and try again.", @"")
                                                             preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"")
                                               style:UIAlertActionStyleCancel
                                             handler:^(UIAlertAction *action) {
                                             }]];
        [self presentViewController:ac animated:YES completion:nil];
    }];
}

- (void) updateAccountIfNeeded:(void(^)(BOOL success, BOOL updated, NSError* error))completion
{
    // If updated less than 5 minutes ago, keep it as is.
    if (!self.account || [self.account.syncDate timeIntervalSinceNow] > -5*60)
    {
        if (completion) completion(YES, NO, nil);
        return;
    }

    [self beginSpinning];

    [self.wallet updateAccount:self.account force:YES completion:^(BOOL success, NSError *error) {

        [self endSpinning];
        if (completion) completion(success, success, error);
    }];
}

- (void) beginSpinning
{
    self.spinner.hidden = NO;
    [self.spinner startAnimating];
    self.sendButton.hidden = YES;
    self.btcField.userInteractionEnabled = NO;
    self.fiatField.userInteractionEnabled = NO;
    self.allFundsButton.userInteractionEnabled = NO;
    self.addressField.userInteractionEnabled = NO;
    self.scanButton.userInteractionEnabled = NO;
}

- (void) endSpinning
{
    self.spinner.hidden = YES;
    [self.spinner stopAnimating];
    self.sendButton.hidden = NO;
    self.btcField.userInteractionEnabled = YES;
    self.fiatField.userInteractionEnabled = YES;
    self.allFundsButton.userInteractionEnabled = YES;
    self.addressField.userInteractionEnabled = YES;
    self.scanButton.userInteractionEnabled = YES;
}

- (void) complete:(BOOL)sent
{
    [self.btcField resignFirstResponder];
    [self.fiatField resignFirstResponder];
    if (self.completionBlock) self.completionBlock(sent);
    self.completionBlock = nil;
}

- (IBAction)useAllFunds:(id)sender
{
    // Compute transaction with all available unspent outputs,
    // figure the required fees and put the difference as a spending amount.

    // Address may not be entered yet, so use dummy address.
    BTCAddress* address = self.spendingAddress ?: [BTCPublicKeyAddress addressWithData:BTCZero160()];

    BTCTransactionBuilder* builder = [[BTCTransactionBuilder alloc] init];
    builder.dataSource = self;
    builder.changeAddress = address; // outputs is empty array, spending all to change address which must be destination address.
    builder.shouldSign = NO;
    builder.feeRate = MYCFeeRate;

    NSError* berror = nil;
    BTCTransactionBuilderResult* result = [builder buildTransaction:&berror];
    if (result)
    {
        self.spendingAmount = result.outputsAmount;
        self.btcField.text = [self.wallet.btcFormatterNaked stringFromAmount:self.spendingAmount];
        [self didEditBtc:nil];
    }
}

- (IBAction)switchToBTC:(id)sender
{
    self.fiatInput = !self.fiatInput;
    if (self.fiatInput) [self.fiatField becomeFirstResponder];
    else [self.btcField becomeFirstResponder];
}

- (IBAction)switchToFiat:(id)sender
{
    [self switchToBTC:sender];
}

- (IBAction)scan:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"MYCSendWithScanner"];

    UIView* targetView = self.view;
    CGRect rect = [targetView convertRect:self.addressField.bounds fromView:self.addressField];

    [MYCScannerView checkPermissionToUseCamera:^(BOOL granted) {

        if (!granted)
        {
            UIAlertController* ac = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Camera Access", @"")
                                                                        message:NSLocalizedString(@"Please allow camera access in system settings.", @"")
                                                                 preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"OK", @"")
                                                   style:UIAlertActionStyleCancel
                                                 handler:^(UIAlertAction *action) {}]];
            [self presentViewController:ac animated:YES completion:nil];

            return;
        }

        self.scannerView = [MYCScannerView presentFromRect:rect inView:targetView detection:^(NSString *message) {

            // 1. Try to read a valid address.
            BTCAddress* address = [[BTCAddress addressWithBase58String:message] publicAddress];
            BTCSatoshi amount = -1;

            if (!address)
            {
                // 2. Try to read a valid 'bitcoin:' URL.
                NSURL* url = [NSURL URLWithString:message];

                BTCBitcoinURL* bitcoinURL = [[BTCBitcoinURL alloc] initWithURL:url];

                if (bitcoinURL)
                {
                    address = [bitcoinURL.address publicAddress];
                    amount = bitcoinURL.amount;
                }
            }

            if (address)
            {
                if (!!address.isTestnet == !!self.wallet.isTestnet)
                {
                    self.addressField.text = address.base58String;
                    [self updateAddressView];

                    if (amount >= 0)
                    {
                        self.spendingAmount = amount;
                        self.btcField.text = [self.wallet.btcFormatterNaked stringFromAmount:self.spendingAmount];
                        [self didEditBtc:nil];
                        [self updateAmounts];
                    }

                    // Jump in amount field.
                    [(self.fiatInput ? self.fiatField : self.btcField) becomeFirstResponder];

                    [self.scannerView dismiss];
                    self.scannerView = nil;
                }
                else
                {
                    self.scannerView.errorMessage = NSLocalizedString(@"Address does not belong to Bitcoin network", @"");
                }
            }
            else
            {
                self.scannerView.errorMessage = NSLocalizedString(@"Not a valid Bitcoin address or payment request", @"");
            }

        }];
    }];
}








#pragma mark - BTCTransactionBuilderDataSource


- (NSEnumerator* /* [BTCTransactionOutput] */) unspentOutputsForTransactionBuilder:(BTCTransactionBuilder*)txbuilder
{
    if (self.account)
    {
        __block NSArray* unspents = nil;
        [self.wallet inDatabase:^(FMDatabase *db) {
            unspents = [MYCUnspentOutput loadOutputsForAccount:self.account.accountIndex database:db];
        }];

        NSMutableArray* utxos = [NSMutableArray array];

        for (MYCUnspentOutput* unspent in unspents)
        {
            //MYCLog(@"unspent: %@: %@", @(unspent.blockHeight), @(unspent.value));
            BTCTransactionOutput* utxo = unspent.transactionOutput;
            utxo.userInfo = @{@"MYCUnspentOutput": unspent };
            [utxos addObject:utxo];
        }

        return [utxos objectEnumerator];
    }
    else
    {
        return [self.unspentOutputs objectEnumerator];
    }
}

- (BTCKey*) transactionBuilder:(BTCTransactionBuilder*)txbuilder keyForUnspentOutput:(BTCTransactionOutput*)txout
{
    // This userInfo key is set in previous call when we provide unspents to the builder.
    MYCUnspentOutput* unspent = txout.userInfo[@"MYCUnspentOutput"];

    if (unspent)
    {
        NSAssert(unspent, @"sanity check");

        __block BTCKey* key = nil;
        [self.wallet unlockWallet:^(MYCUnlockedWallet *unlockedWallet) {

            BTCKeychain* accountKeychain = [unlockedWallet.keychain keychainForAccount:(uint32_t)self.account.accountIndex];

            NSAssert(accountKeychain, @"sanity check");

            key = [[accountKeychain derivedKeychainAtIndex:(uint32_t)unspent.change] keyAtIndex:(uint32_t)unspent.keyIndex];

            NSAssert(key, @"sanity check");

        } reason:nil]; // should be already unlocked

        return key; // will clear on dealloc.
    }
    else
    {
        return self.key;
    }
}








#pragma mark - Implementation



- (NSString*) formatAmountInSelectedCurrency:(BTCSatoshi)amount
{
    if (self.fiatInput)
    {
        return [self.wallet.fiatFormatter stringFromNumber:[self.wallet.currencyConverter fiatFromBitcoin:amount]];
    }
    return [self.wallet.btcFormatter stringFromAmount:amount];
}


- (void) updateTotalBalance
{
    BTCSatoshi spendableAmount = [self spendableAmount];
    self.allFundsLabel.text = [self formatAmountInSelectedCurrency:spendableAmount];
    self.allFundsButton.enabled = (spendableAmount > 0);
}

- (BTCSatoshi) spendableAmount
{
    if (self.account)
    {
        return self.account.spendableAmount;
    }
    else if (self.unspentOutputs)
    {
        BTCSatoshi balance = 0;
        for (BTCTransactionOutput* txout in self.unspentOutputs)
        {
            balance += txout.value;
        }
        return balance;
    }
    return 0;
}

- (void) updateAddressView
{
    NSString* addrString = self.addressField.text;

    if (self.defaultAddress && self.defaultAddressLabel &&
        ([addrString isEqualToString:self.defaultAddressLabel] || [addrString isEqualToString:@""]))
    {
        if (self.addressField.isFirstResponder)
        {
            self.addressField.text = @"";
            addrString = @"";
        }
        else
        {
            self.scanButton.hidden = NO;
            self.addressField.text = self.defaultAddressLabel;
            self.addressField.textColor = [UIColor blackColor];
            self.addressValid = YES;
            self.spendingAddress = self.defaultAddress;
            [self updateSendButton];
            return;
        }
    }

    self.scanButton.hidden = (addrString.length > 0);

    self.addressField.textColor = [UIColor blackColor];

    self.addressValid = NO;
    self.spendingAddress = nil;

    if (addrString.length > 0)
    {
        // Check if that's the valid address.
        BTCAddress* addr = [BTCAddress addressWithBase58String:addrString];
        if (!addr) // parse failure or checksum failure
        {
            // Show in red only when not editing or when it's surely incorrect.
            if (!self.addressField.isFirstResponder || addrString.length >= 34)
            {
                self.addressField.textColor = [UIColor redColor];
            }
        }
        else
        {
            if (!!self.wallet.isTestnet == !!addr.isTestnet)
            {
                self.addressValid = YES;
                self.spendingAddress = addr;
            }
            else
            {
                self.addressField.textColor = [UIColor redColor];
            }
        }
    }

    [self updateSendButton];
}

- (void) updateSendButton
{
    //self.sendButton.enabled = self.addressValid && self.amountValid;
    self.sendButton.enabled = YES;
    self.sendButton.alpha = (self.addressValid && self.amountValid) ? 1.0 : 0.4;
}

- (void) updateAmounts
{
    self.amountValid = NO;

    self.btcField.textColor = [UIColor blackColor];
    self.fiatField.textColor = [UIColor blackColor];

    self.feeLabel.hidden = YES;

    if (self.spendingAmount > 0)
    {
        self.feeLabel.hidden = NO;

        // Compute transaction and figure if it's spendable or not.
        // Update fee and color amounts.
        // Set self.amountValid to YES if everything is okay.

        // Address may not be entered yet, so use dummy address.
        BTCAddress* address = self.spendingAddress ?: [BTCPublicKeyAddress addressWithData:BTCZero160()];

        BTCTransactionBuilder* builder = [[BTCTransactionBuilder alloc] init];
        builder.dataSource = self;
        builder.outputs = @[ [[BTCTransactionOutput alloc] initWithValue:self.spendingAmount address:address] ];
        builder.changeAddress = self.changeAddress ?: self.account.internalAddress;
        builder.shouldSign = NO;
        builder.feeRate = MYCFeeRate;

        NSError* berror = nil;
        BTCTransactionBuilderResult* result = [builder buildTransaction:&berror];
        if (!result)
        {
            self.btcField.textColor = [UIColor redColor];
            self.fiatField.textColor = [UIColor redColor];
            self.feeLabel.text = NSLocalizedString(@"Insufficient funds", @"");
        }
        else
        {
            self.amountValid = YES;
            NSString* feeString = [self formatAmountInSelectedCurrency:result.fee];
            self.feeLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Fee: %@", @""), feeString];
        }
    }
    [self updateSendButton];
    [self updateUnits];
}

- (void) updateUnits
{
    [self.btcButton setTitle:self.wallet.btcFormatter.standaloneSymbol forState:UIControlStateNormal];
    [self.fiatButton setTitle:self.wallet.fiatFormatter.currencySymbol forState:UIControlStateNormal];

    self.btcField.placeholder = self.wallet.btcFormatter.placeholderText;
}


- (void) setFiatInput:(BOOL)fiatInput
{
    if (_fiatInput == fiatInput) return;

    _fiatInput = fiatInput;

    [MYCWallet currentWallet].preferredCurrency = _fiatInput ? MYCWalletPreferredCurrencyFiat : MYCWalletPreferredCurrencyBTC;

    // Exchange fonts

    UIFont* btcFieldFont = self.btcField.font;
    UIFont* fiatFieldFont = self.fiatField.font;

    self.btcField.font = fiatFieldFont;
    self.fiatField.font = btcFieldFont;

    UIFont* btcButtonFont = self.btcButton.titleLabel.font;
    UIFont* fiatButtonFont = self.fiatButton.titleLabel.font;

    self.btcButton.titleLabel.font = fiatButtonFont;
    self.fiatButton.titleLabel.font = btcButtonFont;

    [self updateAmounts];
    [self updateTotalBalance];
}

- (IBAction)didBeginEditingBtc:(id)sender
{
    self.fiatInput = NO;
    [self setEditing:YES animated:YES];
}

- (IBAction)didBeginEditingFiat:(id)sender
{
    self.fiatInput = YES;
    [self setEditing:YES animated:YES];
}

- (IBAction)didEditBtc:(id)sender
{
    self.spendingAmount = [self.wallet.btcFormatter amountFromString:self.btcField.text];
    self.fiatField.text = [self.wallet.fiatFormatterNaked
                           stringFromNumber:[self.wallet.currencyConverter fiatFromBitcoin:self.spendingAmount]];

    if (self.btcField.text.length == 0)
    {
        self.fiatField.text = @"";
    }
}

- (IBAction)didEditFiat:(id)sender
{
    NSNumber* fiatAmount = [self.wallet.fiatFormatter numberFromString:self.fiatField.text];
    self.spendingAmount = [self.wallet.currencyConverter bitcoinFromFiat:[NSDecimalNumber decimalNumberWithDecimal:fiatAmount.decimalValue]];
    self.btcField.text = [self.wallet.btcFormatterNaked stringFromAmount:self.spendingAmount];

    if (self.fiatField.text.length == 0)
    {
        self.btcField.text = @"";
    }
}


- (IBAction)didBeginEditingAddress:(id)sender
{
    [self updateAddressView];
}

- (IBAction)didEditAddress:(id)sender
{
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"MYCSendWithScanner"];
    [self updateAddressView];
}

- (IBAction)didEndEditingAddress:(id)sender
{
    [self updateAddressView];
}

- (BOOL) textFieldShouldReturn:(UITextField *)textField
{
    if (textField == self.addressField)
    {
        if (self.fiatInput)
        {
            [self.fiatField becomeFirstResponder];
        }
        else
        {
            [self.btcField becomeFirstResponder];
        }
    }
    else if (textField == self.btcField || textField == self.fiatField)
    {
        [self.view endEditing:YES];
    }

    return YES;
}


@end
