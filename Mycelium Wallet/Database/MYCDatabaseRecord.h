#import <FMDB/FMDatabase.h>


// =============================================================================
#pragma mark - Errors

extern NSString* const MYCDatabaseRecordErrorDomain;
typedef NS_ENUM(NSInteger, MYCDatabaseRecordErrorCode) {    // Code for NSErrors of domain MYCDatabaseRecordErrorDomain
    MYCDatabaseRecordValidationErrorCode,
};
extern NSString* const MYCDatabaseRecordColumnKey;          // Defined for NSErrors of code MYCDatabaseRecordValidationErrorCode


// =============================================================================
#pragma mark - MYCDatabaseRecord

@interface MYCDatabaseRecord : NSObject<NSCopying>


#pragma mark - Configuration

/**
 You may override those to get automatic saving. columns should include primaryKeyName if not nil.
 */
+ (NSString *)tableName;
+ (id)primaryKeyName;   // defaults to "id", may contain an array of strings for multi-column primary keys.
+ (NSArray *)columnNames;

/**
 * Use the MYCDatabaseColumn macro to fill the array returned by columns, and reduce the risk of referencing an obsolete property.
 *
 *     @interface MyObject : MYCDatabaseRecord
 *     @property (nonatomic) NSString *name;
 *     @end
 *
 *     @implementation MyObject
 *     + (NSArray *)columns
 *     {
 *         return @[MYCDatabaseColumn(name)];
 *     }
 *     @end
 */
#define MYCDatabaseColumn(prop) (NSStringFromSelector(@selector(prop)))


#pragma mark - Loading & Creation

/**
 * Will call setValue:forKey: for all the keys in dictionary for which the receiver implements a set<Key>: method.
 */
- (instancetype)initWithDictionary:(NSDictionary *)dict;

///**
// * Returns a dictionary { primaryKey: instance }
// * Each key could be a scalar string/number or an array of scalars (for multi-column primary keys).
// */
//+ (NSDictionary *)loadWithPrimaryKeys:(NSSet *)primaryKeys fromDatabase:(FMDatabase *)db;

/**
 * Returns an object, or nil if it is not found.
 */
+ (instancetype)loadWithPrimaryKey:(id)primaryKey fromDatabase:(FMDatabase *)db;

// Array of dictionaries with given attributes
+ (NSArray*) loadAttributes:(NSArray*)attrs condition:(NSString*)condition fromDatabase:(FMDatabase*)db;
+ (NSArray*) loadAttributes:(NSArray*)attrs condition:(NSString*)condition params:(id)params fromDatabase:(FMDatabase*)db;

// Array of dictionaries for a given column
+ (NSArray*) loadValuesForKey:(NSString*)attr condition:(NSString*)condition fromDatabase:(FMDatabase*)db;
+ (NSArray*) loadValuesForKey:(NSString*)attr condition:(NSString*)condition params:(id)params fromDatabase:(FMDatabase*)db;

/**
 Loads instances with a given condition. Arguments for the condition placeholders could either be an array, or a dictionary.
 Default limit is NSNotFound which means no limit.
 Default offset is zero.
 Example 1: [MYCWalletAccount loadWithCondition:@"archived = ?" params: @[ @NO ] fromDatabase:db]
 Example 2: [MYCWalletAccount loadWithCondition:@"archived = :flag" params: @{@"flag": @NO } fromDatabase:db]
 */
+ (NSArray*)loadAllFromDatabase:(FMDatabase*)db;
+ (NSArray*)loadWithCondition:(NSString*)condition fromDatabase:(FMDatabase*)db;
+ (NSArray*)loadWithCondition:(NSString*)condition params:(id)params fromDatabase:(FMDatabase*)db;

/**
 * Reloads all attributes from the database.
 */
- (BOOL)reloadFromDatabase:(FMDatabase *)db;

/**
 * If you override this, always call super.
 */
- (void) didLoadFromDatabase:(FMDatabase*)db;


/**
 Similar to load* methods, but only performs counting.
 */
+ (NSUInteger)countAllFromDatabase:(FMDatabase*)db;
+ (NSUInteger)countWithCondition:(NSString*)condition fromDatabase:(FMDatabase*)db;
+ (NSUInteger)countWithCondition:(NSString*)condition params:(id)params fromDatabase:(FMDatabase*)db;




#pragma mark - Modifying, Saving & Deleting

/**
 * Call setValue:forKey: for all the keys in dictionary for which the receiver
 * implements a set<Key>: method.
 */
- (void)updateFromDictionary:(NSDictionary*)dict;

/**
 * Inserts as a record in the database.
 *
 * @see saveInDatabase:error:
 */
- (BOOL)insertInDatabase:(FMDatabase *)db error:(NSError **)outError;

/**
 * Updates the record in the database.
 * The receiver must have a non-nil primary key and an existing record in the database.
 *
 * @see saveInDatabase:error:
 */
- (BOOL)updateInDatabase:(FMDatabase *)db error:(NSError **)outError;

/**
 * Attempts to find the record and updateInDatabase, or insert if none found.
 * The class of the receiver must have a primary key column.
 */
- (BOOL)saveInDatabase:(FMDatabase *)db error:(NSError **)outError;

/**
 */
- (BOOL)deleteFromDatabase:(FMDatabase *)db error:(NSError **)outError;

/**
 */
+ (BOOL)deleteAllFromDatabase:(FMDatabase *)db error:(NSError **)outError;


#pragma mark - Validation

/**
 * Default implementation will call validateValue:forKey:error: for all columns,
 * but the primary key for validateForInsert.
 */
- (BOOL)validateForInsert:(NSError **)outError;
- (BOOL)validateForUpdate:(NSError **)outError;

/**
 * Commodity method.
 * Returns an error of domain MYCDatabaseRecordErrorDomain & code MYCDatabaseRecordValidationErrorCode
 */
+ (NSError*)validationErrorForColumn:(NSString*)column withMessage:(NSString*)message;


/*
 * Macros below can help writing validation methods:
 *
 *     - (BOOL)validateAmount:(id *)value error:(NSError **)outError
 *     {
 *         PValidateNonNilOrFail(value, outError);
 *         PValidateIsKindOfClassOrFail(value, NSNumber, outError);
 *
 *         NSNumber *number = (NSNumber *)(*value);
 *
 *         // Check sign
 *         if ([number compare:[NSNumber numberWithInt:0]] == NSOrderedAscending) {
 *             PFailWithValidationError(value, @"Can't be negative", outError);
 *         }
 *
 *         return YES;
 *     }
 */

#define _PPropertyNameFromValidationMethodSelector(cmd) ({\
    NSString *propertyName = [[[NSStringFromSelector(cmd) componentsSeparatedByString:@":"] firstObject] substringFromIndex:8];\
    [[[propertyName substringToIndex:1] lowercaseString] stringByAppendingString:[propertyName substringFromIndex:1]];\
})

#define _PValidationError(value, errorMessage) ({\
    NSString *propertyName = _PPropertyNameFromValidationMethodSelector(_cmd);\
    [MYCDatabaseRecord validationErrorForColumn:propertyName withMessage:[NSString stringWithFormat:@"Error for %@.%@ with value %@: %@", [self class], propertyName, *value, errorMessage]];\
})

#define PFailWithValidationError(value, errorMessage, outError) do {\
    if (outError != NULL) *outError = _PValidationError(value, errorMessage);\
    return NO;\
} while(0);

#define PValidateNonNilOrFail(value, outError) do {\
    if (*value == nil) {\
        PFailWithValidationError(value, @"can not be null", outError);\
    }\
} while(0);

#define PValidateIsKindOfClassOrFail(value, cls, outError) do {\
    if (*value && ![*value isKindOfClass:[cls class]]) {\
        PFailWithValidationError(value, ([NSString stringWithFormat:@"is not a %@", [cls class]]), outError);\
    }\
} while(0);




@end
