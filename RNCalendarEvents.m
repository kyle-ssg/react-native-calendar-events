#import "RNCalendarEvents.h"
#import "RCTConvert.h"
#import "RCTUtils.h"
#import <EventKit/EventKit.h>

@interface RNCalendarEvents ()
@property (nonatomic, strong) EKEventStore *eventStore;
@property (copy, nonatomic) NSArray *calendarEvents;
@property (nonatomic) BOOL isAccessToEventStoreGranted;
@end

static NSString *const _id = @"id";
static NSString *const _title = @"title";
static NSString *const _location = @"location";
static NSString *const _lat = @"lat";
static NSString *const _lng = @"lng";
static NSString *const _startDate = @"startDate";
static NSString *const _endDate = @"endDate";
static NSString *const _allDay = @"allDay";
static NSString *const _notes = @"notes";
static NSString *const _url = @"url";
static NSString *const _alarms = @"alarms";
static NSString *const _recurrence = @"recurrence";
static NSString *const _occurrenceDate = @"occurrenceDate";
static NSString *const _isDetached = @"isDetached";

@implementation RNCalendarEvents

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE()

#pragma mark -
#pragma mark Event Store Initialize

- (EKEventStore *)eventStore
{
    if (!_eventStore) {
        _eventStore = [[EKEventStore alloc] init];
    }
    return _eventStore;
}

- (NSArray *)calendarEvents
{
    if (!_calendarEvents) {
        _calendarEvents = [[NSArray alloc] init];
    }
    return _calendarEvents;
}

#pragma mark -
#pragma mark Event Store Authorization

- (NSString *)authorizationStatusForEventStore
{
    EKAuthorizationStatus status = [EKEventStore authorizationStatusForEntityType:EKEntityTypeEvent];

    switch (status) {
        case EKAuthorizationStatusDenied:
            self.isAccessToEventStoreGranted = NO;
            return @"denied";
        case EKAuthorizationStatusRestricted:
            self.isAccessToEventStoreGranted = NO;
            return @"restricted";
        case EKAuthorizationStatusAuthorized:
            self.isAccessToEventStoreGranted = YES;
            return @"authorized";
        case EKAuthorizationStatusNotDetermined: {
            return @"undetermined";
        }
    }
}

#pragma mark -
#pragma mark Event Store Accessors

- (NSDictionary *)buildAndSaveEvent:(NSDictionary *)details
{
    if ([[self authorizationStatusForEventStore] isEqualToString:@"granted"]) {
        return @{@"success": [NSNull null], @"error": @"unauthorized to access calendar"};
    }

    EKEvent *calendarEvent = nil;
    NSString *eventId = [RCTConvert NSString:details[_id]];
    NSString *title = [RCTConvert NSString:details[_title]];
    NSString *location = [RCTConvert NSString:details[_location]];
    NSDate *startDate = [RCTConvert NSDate:details[_startDate]];
    NSDate *endDate = [RCTConvert NSDate:details[_endDate]];
    NSNumber *allDay = [RCTConvert NSNumber:details[_allDay]];
    NSString *notes = [RCTConvert NSString:details[_notes]];
    NSString *url = [RCTConvert NSString:details[_url]];
    NSArray *alarms = [RCTConvert NSArray:details[_alarms]];
    NSString *recurrence = [RCTConvert NSString:details[_recurrence]];

    if (eventId) {
        calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];

    } else {
        calendarEvent = [EKEvent eventWithEventStore:self.eventStore];
        calendarEvent.calendar = [self.eventStore defaultCalendarForNewEvents];
    }

    if (title) {
        calendarEvent.title = title;
    }

    if (location) {
        calendarEvent.location = location;
    }

    if (startDate) {
        calendarEvent.startDate = startDate;
    }

    if (endDate) {
        calendarEvent.endDate = endDate;
    }
    
    if (allDay) {
        calendarEvent.allDay = [allDay boolValue];
    }

    if (notes) {
        calendarEvent.notes = notes;
    }

    if (alarms) {
        calendarEvent.alarms = [self createCalendarEventAlarms:alarms];
    }

    if (recurrence) {
        EKRecurrenceRule *rule = [self createRecurrenceRule:recurrence];
        if (rule) {
            calendarEvent.recurrenceRules = [NSArray arrayWithObject:rule];
        }
    }

    NSURL *URL = [NSURL URLWithString:[url stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    if (URL) {
        calendarEvent.URL = URL;
    }

    return [self saveEvent:calendarEvent];
}

- (NSDictionary *)saveEvent:(EKEvent *)calendarEvent
{
    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:@{@"success": [NSNull null], @"error": [NSNull null]}];

    NSError *error = nil;
    BOOL success = [self.eventStore saveEvent:calendarEvent span:EKSpanFutureEvents commit:YES error:&error];

    if (!success) {
        [response setValue:[error.userInfo valueForKey:@"NSLocalizedDescription"] forKey:@"error"];
    } else {
        [response setValue:calendarEvent.calendarItemIdentifier forKey:@"success"];
    }
    return [response copy];
}

- (NSDictionary *)findById:(NSString *)eventId
{
    if ([[self authorizationStatusForEventStore] isEqualToString:@"granted"]) {
        return @{@"success": [NSNull null], @"error": @"unauthorized to access calendar"};
    }

    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:@{@"success": [NSNull null]}];

    EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];

    if (calendarEvent) {
        [response setValue:[self serializeCalendarEvent:calendarEvent] forKey:@"success"];
    }
    return [response copy];
}

- (NSDictionary *)deleteEvent:(NSString *)eventId span:(EKSpan *)span
{
    if ([[self authorizationStatusForEventStore] isEqualToString:@"granted"]) {
        return @{@"success": [NSNull null], @"error": @"unauthorized to access calendar"};
    }

    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithDictionary:@{@"success": [NSNull null], @"error": [NSNull null]}];

    EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];

    NSError *error = nil;
    BOOL success = [self.eventStore removeEvent:calendarEvent span:span commit:YES error:&error];

    if (!success) {
        [response setValue:[error.userInfo valueForKey:@"NSLocalizedDescription"] forKey:@"error"];
    } else {
        [response setValue:@YES forKey:@"success"];
    }
    return [response copy];
}

#pragma mark -
#pragma mark Alarms

- (EKAlarm *)createCalendarEventAlarm:(NSDictionary *)alarm
{
    EKAlarm *calendarEventAlarm = nil;
    id alarmDate = [alarm valueForKey:@"date"];

    if ([alarmDate isKindOfClass:[NSString class]]) {
        calendarEventAlarm = [EKAlarm alarmWithAbsoluteDate:[RCTConvert NSDate:alarmDate]];
    } else if ([alarmDate isKindOfClass:[NSNumber class]]) {
        int minutes = [alarmDate intValue];
        calendarEventAlarm = [EKAlarm alarmWithRelativeOffset:(60 * minutes)];
    } else {
        calendarEventAlarm = [[EKAlarm alloc] init];
    }

    if ([alarm objectForKey:@"structuredLocation"] && [[alarm objectForKey:@"structuredLocation"] count]) {
        NSDictionary *locationOptions = [alarm valueForKey:@"structuredLocation"];
        NSDictionary *geo = [locationOptions valueForKey:@"coords"];
        CLLocation *geoLocation = [[CLLocation alloc] initWithLatitude:[[geo valueForKey:@"latitude"] doubleValue]
                                                             longitude:[[geo valueForKey:@"longitude"] doubleValue]];

        calendarEventAlarm.structuredLocation = [EKStructuredLocation locationWithTitle:[locationOptions valueForKey:@"title"]];
        calendarEventAlarm.structuredLocation.geoLocation = geoLocation;
        calendarEventAlarm.structuredLocation.radius = [[locationOptions valueForKey:@"radius"] doubleValue];

        if ([[locationOptions valueForKey:@"proximity"] isEqualToString:@"enter"]) {
            calendarEventAlarm.proximity = EKAlarmProximityEnter;
        } else if ([[locationOptions valueForKey:@"proximity"] isEqualToString:@"leave"]) {
            calendarEventAlarm.proximity = EKAlarmProximityLeave;
        } else {
            calendarEventAlarm.proximity = EKAlarmProximityNone;
        }
    }
    return calendarEventAlarm;
}

- (NSArray *)createCalendarEventAlarms:(NSArray *)alarms
{
    NSMutableArray *calendarEventAlarms = [[NSMutableArray alloc] init];
    for (NSDictionary *alarm in alarms) {
        if ([alarm count] && ([alarm valueForKey:@"date"] || [alarm objectForKey:@"structuredLocation"])) {
            EKAlarm *reminderAlarm = [self createCalendarEventAlarm:alarm];
            [calendarEventAlarms addObject:reminderAlarm];
        }
    }
    return [calendarEventAlarms copy];
}

- (void)addCalendarEventAlarm:(NSString *)eventId alarm:(NSDictionary *)alarm
{
    if (!self.isAccessToEventStoreGranted) {
        return;
    }

    EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];
    EKAlarm *calendarEventAlarm = [self createCalendarEventAlarm:alarm];
    [calendarEvent addAlarm:calendarEventAlarm];

    [self saveEvent:calendarEvent];
}

- (void)addCalendarEventAlarms:(NSString *)eventId alarms:(NSArray *)alarms
{
    if (!self.isAccessToEventStoreGranted) {
        return;
    }

    EKEvent *calendarEvent = (EKEvent *)[self.eventStore calendarItemWithIdentifier:eventId];
    calendarEvent.alarms = [self createCalendarEventAlarms:alarms];

    [self saveEvent:calendarEvent];
}

#pragma mark -
#pragma mark RecurrenceRules

-(EKRecurrenceFrequency)frequencyMatchingName:(NSString *)name
{
    EKRecurrenceFrequency recurrence = EKRecurrenceFrequencyDaily;

    if ([name isEqualToString:@"weekly"]) {
        recurrence = EKRecurrenceFrequencyWeekly;
    } else if ([name isEqualToString:@"monthly"]) {
        recurrence = EKRecurrenceFrequencyMonthly;
    } else if ([name isEqualToString:@"yearly"]) {
        recurrence = EKRecurrenceFrequencyYearly;
    }
    return recurrence;
}

-(EKRecurrenceRule *)createRecurrenceRule:(NSString *)frequency
{
    EKRecurrenceRule *rule = nil;
    NSArray *validFrequencyTypes = @[@"daily", @"weekly", @"monthly", @"yearly"];

    if ([validFrequencyTypes containsObject:frequency]) {
        rule = [[EKRecurrenceRule alloc] initRecurrenceWithFrequency:[self frequencyMatchingName:frequency]
                                                            interval:1
                                                                 end:nil];
    }
    return rule;
}

-(NSString *)nameMatchingFrequency:(EKRecurrenceFrequency)frequency
{
    switch (frequency) {
        case EKRecurrenceFrequencyWeekly:
            return @"weekly";
        case EKRecurrenceFrequencyMonthly:
            return @"monthly";
        case EKRecurrenceFrequencyYearly:
            return @"yearly";
        default:
            return @"daily";
    }
}

#pragma mark -
#pragma mark Serializers

- (NSArray *)serializeCalendarEvents:(NSArray *)calendarEvents
{
    NSMutableArray *serializedCalendarEvents = [[NSMutableArray alloc] init];

    NSDictionary *emptyCalendarEvent = @{
                                         _title: @"",
                                         _location: @"",
                                         _lat: @"",
                                         _lng: @"",
                                         _startDate: @"",
                                         _endDate: @"",
                                         _allDay: @NO,
                                         _notes: @"",
                                         _url: @"",
                                         _alarms: @[],
                                         _recurrence: @""
                                         };

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    [dateFormatter setTimeZone:timeZone];
    [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setDateFormat: @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z"];

    for (EKEvent *event in calendarEvents) {

        [serializedCalendarEvents addObject:[self serializeCalendarEvent:event]];
    }

    return [serializedCalendarEvents copy];
}

- (NSDictionary *)serializeCalendarEvent:(EKEvent *)event
{

    NSDictionary *emptyCalendarEvent = @{
                                         _title: @"",
                                         _location: @"",
                                         _lat: @"",
                                         _lng: @"",
                                         _startDate: @"",
                                         _endDate: @"",
                                         _allDay: @NO,
                                         _notes: @"",
                                         _url: @"",
                                         _alarms: @[],
                                         _recurrence: @""
                                         };

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    [dateFormatter setTimeZone:timeZone];
    [dateFormatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    [dateFormatter setDateFormat: @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z"];


    NSMutableDictionary *formedCalendarEvent = [NSMutableDictionary dictionaryWithDictionary:emptyCalendarEvent];

    if (event.calendarItemIdentifier) {
        [formedCalendarEvent setValue:event.calendarItemIdentifier forKey:_id];
    }

    if (event.title) {
        [formedCalendarEvent setValue:event.title forKey:_title];
    }

    if (event.notes) {
        [formedCalendarEvent setValue:event.notes forKey:_notes];
    }

    if (event.URL) {
        [formedCalendarEvent setValue:[event.URL absoluteString] forKey:_url];
    }

    if (event.location) {
        [formedCalendarEvent setValue:event.location forKey:_location];
    }
    
    if (event.structuredLocation) {
        
        NSNumber *lat = [NSNumber numberWithDouble:event.structuredLocation.geoLocation.coordinate.latitude];
        NSNumber *lng = [NSNumber numberWithDouble:event.structuredLocation.geoLocation.coordinate.longitude];
        [formedCalendarEvent setValue:lng forKey:_lng];
        [formedCalendarEvent setValue:lat forKey:_lat];
    }
    

    if (event.hasAlarms) {
        NSMutableArray *alarms = [[NSMutableArray alloc] init];

        for (EKAlarm *alarm in event.alarms) {

            NSMutableDictionary *formattedAlarm = [[NSMutableDictionary alloc] init];
            NSString *alarmDate = nil;

            if (alarm.absoluteDate) {
                alarmDate = [dateFormatter stringFromDate:alarm.absoluteDate];
            } else if (alarm.relativeOffset) {
                NSDate *calendarEventStartDate = nil;
                if (event.startDate) {
                    calendarEventStartDate = event.startDate;
                } else {
                    calendarEventStartDate = [NSDate date];
                }
                alarmDate = [dateFormatter stringFromDate:[NSDate dateWithTimeInterval:alarm.relativeOffset
                                                                             sinceDate:calendarEventStartDate]];
            }
            [formattedAlarm setValue:alarmDate forKey:@"date"];

            if (alarm.structuredLocation) {
                NSString *proximity = nil;
                switch (alarm.proximity) {
                    case EKAlarmProximityEnter:
                        proximity = @"enter";
                        break;
                    case EKAlarmProximityLeave:
                        proximity = @"leave";
                        break;
                    default:
                        proximity = @"None";
                        break;
                }
                [formattedAlarm setValue:@{
                                           @"title": alarm.structuredLocation.title,
                                           @"proximity": proximity,
                                           @"radius": @(alarm.structuredLocation.radius),
                                           @"coords": @{
                                                   @"latitude": @(alarm.structuredLocation.geoLocation.coordinate.latitude),
                                                   @"longitude": @(alarm.structuredLocation.geoLocation.coordinate.longitude)
                                                   }}
                                  forKey:@"structuredLocation"];

            }
            [alarms addObject:formattedAlarm];
        }
        [formedCalendarEvent setValue:alarms forKey:_alarms];
    }

    if (event.startDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.startDate] forKey:_startDate];
    }

    if (event.endDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.endDate] forKey:_endDate];
    }

    if (event.occurrenceDate) {
        [formedCalendarEvent setValue:[dateFormatter stringFromDate:event.occurrenceDate] forKey:_occurrenceDate];
    }

    [formedCalendarEvent setValue:[NSNumber numberWithBool:event.isDetached] forKey:_isDetached];

    [formedCalendarEvent setValue:[NSNumber numberWithBool:event.allDay] forKey:_allDay];

    if (event.hasRecurrenceRules) {
        NSString *frequencyType = [self nameMatchingFrequency:[[event.recurrenceRules objectAtIndex:0] frequency]];
        [formedCalendarEvent setValue:frequencyType forKey:_recurrence];
    }

    return [formedCalendarEvent copy];
}

#pragma mark -
#pragma mark RCT Exports

RCT_EXPORT_METHOD(authorizationStatus:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSString *status = [self authorizationStatusForEventStore];
    if (status) {
        resolve(status);
    } else {
        reject(@"error", @"authorization status error", nil);
    }
}

RCT_EXPORT_METHOD(authorizeEventStore:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    __weak RNCalendarEvents *weakSelf = self;
    [self.eventStore requestAccessToEntityType:EKEntityTypeEvent completion:^(BOOL granted, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *status = granted ? @"authorized" : @"denied";
            weakSelf.isAccessToEventStoreGranted = granted;
            if (!error) {
                resolve(status);
            } else {
                reject(@"error", @"authorization request error", error);
            }
        });
    }];
}

RCT_EXPORT_METHOD(fetchAllEvents:(NSDate *)startDate endDate:(NSDate *)endDate resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSPredicate *predicate = [self.eventStore predicateForEventsWithStartDate:startDate
                                                                      endDate:endDate
                                                                    calendars:nil];

    __weak RNCalendarEvents *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        weakSelf.calendarEvents = [[weakSelf.eventStore eventsMatchingPredicate:predicate] sortedArrayUsingSelector:@selector(compareStartDateWithEvent:)];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.calendarEvents) {
                resolve([weakSelf serializeCalendarEvents:weakSelf.calendarEvents]);
            } else {
                reject(@"error", @"calendar event request error", nil);
            }
        });
    });
}

RCT_EXPORT_METHOD(findEventById:(NSString *)eventId resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSDictionary *response = [self findById:eventId];

    if (!response) {
        reject(@"error", @"error finding event", nil);
    } else {
        resolve([response valueForKey:@"success"]);
    }
}

RCT_EXPORT_METHOD(saveEvent:(NSString *)title details:(NSDictionary *)details resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithDictionary:details];
    [options setValue:title forKey:_title];

    NSDictionary *response = [self buildAndSaveEvent:options];

    if ([response valueForKey:@"success"] != [NSNull null]) {
        resolve([response valueForKey:@"success"]);
    } else {
        reject(@"error", [response valueForKey:@"error"], nil);
    }
}

RCT_EXPORT_METHOD(removeEvent:(NSString *)eventId resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSDictionary *response = [self deleteEvent:eventId span:EKSpanThisEvent];

    if ([response valueForKey:@"success"] != [NSNull null]) {
        resolve([response valueForKey:@"success"]);
    } else {
        reject(@"error", [response valueForKey:@"error"], nil);
    }
}

RCT_EXPORT_METHOD(removeFutureEvents:(NSString *)eventId resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    NSDictionary *response = [self deleteEvent:eventId span:EKSpanFutureEvents];

    if ([response valueForKey:@"success"] != [NSNull null]) {
        resolve([response valueForKey:@"success"]);
    } else {
        reject(@"error", [response valueForKey:@"error"], nil);
    }
}

@end
