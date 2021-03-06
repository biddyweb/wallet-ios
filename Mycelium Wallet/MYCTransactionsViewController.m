//
//  MYCTransactionsViewController.m
//  Mycelium Wallet
//
//  Created by Oleg Andreev on 29.09.2014.
//  Copyright (c) 2014 Mycelium. All rights reserved.
//

#import "MYCWallet.h"
#import "MYCWalletAccount.h"
#import "MYCTransaction.h"

#import "MYCTransactionsViewController.h"
#import "MYCTransactionTableViewCell.h"
#import "MYCTransactionDetailsViewController.h"

@interface MYCTransactionsViewController () <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic, weak) IBOutlet UITableView* tableView;
@property(nonatomic) MYCWalletAccount* currentAccount;

@property(nonatomic) BTCNumberFormatter* btcFormatter;
@property(nonatomic) NSNumberFormatter* fiatFormatter;

@property(nonatomic) UISegmentedControl* currencyControl;
@end

@implementation MYCTransactionsViewController

- (id) initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])
    {
        self.title = NSLocalizedString(@"Transactions", @"");
        //self.tintColor = [UIColor colorWithHue:13.0f/360.0f saturation:0.79f brightness:1.00f alpha:1.0f];
        //self.tintColor = [UIColor colorWithHue:130.0f/360.0f saturation:0.7f brightness:0.65f alpha:1.0];
        //self.tintColor = [UIColor colorWithHue:28.0f/360.0f saturation:0.8f brightness:0.9f alpha:1.0f];
        //self.tintColor = [UIColor colorWithHue:34.0f/360.0f saturation:0.8f brightness:0.96f alpha:1.0f];
        self.tintColor = [UIColor colorWithHue:208.0f/360.0f saturation:1.0f brightness:1.0f alpha:1.0f];
        
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:NSLocalizedString(@"Transactions", @"") image:[UIImage imageNamed:@"TabTransactions"] selectedImage:[UIImage imageNamed:@"TabTransactionsSelected"]];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(formattersDidUpdate:) name:MYCWalletFormatterDidUpdateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(walletDidReload:) name:MYCWalletDidReloadNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(walletExchangeRateDidUpdate:) name:MYCWalletCurrencyConverterDidUpdateNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(walletDidUpdateAccount:) name:MYCWalletDidUpdateAccountNotification object:nil];
    }
    return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL) shouldOverrideTintColor
{
    // Only override tint color if opened in the context of tabbar (no specific account is selected).
    return !_account;
}

- (MYCWalletAccount*) account
{
    return _account ?: _currentAccount;
}



#pragma mark - Wallet Notifications


- (void) formattersDidUpdate:(NSNotification*)notif
{
    [self updateFormatters];
    [self.tableView reloadData];
}

- (void) walletDidReload:(NSNotification*)notif
{
    [self.tableView reloadData];
}

- (void) walletExchangeRateDidUpdate:(NSNotification*)notif
{
    [self.tableView reloadData];
}

- (void) walletDidUpdateNetworkActivity:(NSNotification*)notif
{
    [self updateRefreshControl];
}

- (void) walletDidUpdateAccount:(NSNotification*)notif
{
    [self.tableView reloadData];
}




- (void)viewDidLoad
{
    [super viewDidLoad];

    [self.tableView registerNib:[UINib nibWithNibName:@"MYCTransactionTableViewCell" bundle:nil] forCellReuseIdentifier:@"cell"];
}


- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    [self updateFormatters];

    // Deselect current row.
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:animated];

    // If no account at all, load currentAccount.
    if (!self.account)
    {
        [[MYCWallet currentWallet] inDatabase:^(FMDatabase *db) {
            self.currentAccount = [MYCWalletAccount loadCurrentAccountFromDatabase:db];
        }];
    }

    // Reload account.
    [[MYCWallet currentWallet] inDatabase:^(FMDatabase *db) {
        if (_currentAccount)
        {
            self.currentAccount = [MYCWalletAccount loadCurrentAccountFromDatabase:db];
        }
        [self.account reloadFromDatabase:db];
    }];

    [self.tableView reloadData];
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    //    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.currencyControl];
    self.navigationItem.titleView = self.currencyControl;
}

- (void) updateRefreshControl
{
    
}

- (void) updateFormatters
{
    self.btcFormatter = [[MYCWallet currentWallet].btcFormatter copy];
    self.btcFormatter.symbolStyle = BTCNumberFormatterSymbolStyleSymbol;
    self.btcFormatter.minimumFractionDigits = self.btcFormatter.maximumFractionDigits;

    self.fiatFormatter = [[MYCWallet currentWallet].fiatFormatter copy];
    self.fiatFormatter.minimumFractionDigits = self.fiatFormatter.maximumFractionDigits;
    self.fiatFormatter.currencySymbol = @"";
    self.fiatFormatter.positiveSuffix = @"";
    self.fiatFormatter.positivePrefix = NSLocalizedString(@"$", @"");
    self.fiatFormatter.negativeSuffix = @"";

    self.currencyControl = [[UISegmentedControl alloc] initWithItems:@[
      [MYCWallet currentWallet].btcFormatter.currencySymbol ?: @"BTC",
      [MYCWallet currentWallet].fiatFormatter.currencySymbol ?: @"USD"]];

    [self.currencyControl setWidth:60 forSegmentAtIndex:0];
    [self.currencyControl setWidth:60 forSegmentAtIndex:1];

    [self.currencyControl addTarget:self action:@selector(currencyDidChange:) forControlEvents:UIControlEventValueChanged];
    self.currencyControl.tintColor = self.tintColor;
    [self updateCurrencyControl];
}

- (void) updateCurrencyControl
{
    switch ([MYCWallet currentWallet].preferredCurrency)
    {
        case MYCWalletPreferredCurrencyBTC:
            self.currencyControl.selectedSegmentIndex = 0;
            break;
        case MYCWalletPreferredCurrencyFiat:
            self.currencyControl.selectedSegmentIndex = 1;
            break;
    }
}

- (void) currencyDidChange:(id)_
{
    if (self.currencyControl.selectedSegmentIndex == 0)
    {
        [MYCWallet currentWallet].preferredCurrency = MYCWalletPreferredCurrencyBTC;
    }
    else if (self.currencyControl.selectedSegmentIndex == 1)
    {
        [MYCWallet currentWallet].preferredCurrency = MYCWalletPreferredCurrencyFiat;
    }
    [self.tableView reloadData];
}

#pragma mark - UITableView


- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    __block NSInteger count = 0;
    [[MYCWallet currentWallet] inDatabase:^(FMDatabase *db) {
        count = [MYCTransaction countTransactionsForAccount:self.account database:db];
    }];
    return count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    MYCTransactionTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    __block MYCTransaction* tx = nil;
    [[MYCWallet currentWallet] inDatabase:^(FMDatabase *db) {
        tx = [MYCTransaction loadTransactionAtIndex:indexPath.row account:self.account database:db];
        [tx loadDetailsFromDatabase:db];
    }];
    cell.transaction = tx;

    NSString* amountString = @"";
    if ([MYCWallet currentWallet].preferredCurrency == MYCWalletPreferredCurrencyBTC) {
        amountString = [self.btcFormatter stringFromAmount:ABS(tx.amountTransferred)];
    }
    else {
        amountString = [self.fiatFormatter stringFromNumber:[[MYCWallet currentWallet].currencyConverter fiatFromBitcoin:ABS(tx.amountTransferred)]];
    }

    if (tx.amountTransferred > 0) {
        amountString = [@"+ " stringByAppendingString:amountString];
    }
    else if (tx.amountTransferred < 0) {
        amountString = [@"– " stringByAppendingString:amountString];
    }

    cell.formattedAmount = amountString;

    return cell;
}

- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    __block MYCTransaction* tx = nil;
    [[MYCWallet currentWallet] inDatabase:^(FMDatabase *db) {
        tx = [MYCTransaction loadTransactionAtIndex:indexPath.row account:self.account database:db];
        [tx loadDetailsFromDatabase:db];
    }];

    MYCTransactionTableViewCell* cell = (id)[tableView cellForRowAtIndexPath:indexPath];

    UIStoryboard* sb = [UIStoryboard storyboardWithName:@"MYCTransactionDetails" bundle:nil];
    MYCTransactionDetailsViewController* vc = [sb instantiateInitialViewController];
    vc.transaction = tx;
    vc.tintColor = self.tintColor;
    vc.redColor = cell.redColor;
    vc.greenColor = cell.greenColor;
    [self.navigationController pushViewController:vc animated:YES];
}

@end
