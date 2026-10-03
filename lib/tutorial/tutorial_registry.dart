import '../logic/dashboard_resolver.dart';
import 'tutorial_definition.dart';
import 'tutorial_step.dart';

class TutorialRegistry {
  static String dashboardId(List<String> roles) =>
      'dashboard.${switch (DashboardResolver.resolve(roles)) {
        DashboardType.ministryLeader => 'ministry_leader',
        DashboardType.ministryWorker => 'ministry_worker',
        final type => type.name,
      }}';
  static final Map<String, TutorialDefinition> definitions = {
    'community_feed': const TutorialDefinition('community_feed', [
      TutorialStep('community.scope', 'Your community',
          'Choose your church, people you follow, or updates from across Grace Connect.'),
      TutorialStep('community.stories', 'Stories',
          'Catch up on short updates from people and churches in your community.'),
      TutorialStep('community.create', 'Share something',
          'Start a post, photo, video or status when you have something to share.'),
      TutorialStep('bottom_nav.feed', 'Meet Reel Grace',
          'Tap Feed again, or hold it, to switch between your feed and Reel Grace.'),
    ]),
    'reel_grace': const TutorialDefinition('reel_grace', [
      TutorialStep('reels.playback', 'Watch and explore',
          'Swipe up for the next reel. Tap a video to pause or continue.'),
      TutorialStep('reels.actions', 'Join the conversation',
          'Like, comment, save or share a reel using these controls.'),
      TutorialStep('reels.options', 'Make it yours',
          'Hold a video or open its menu for auto-scroll and content preferences.'),
    ]),
    'events': const TutorialDefinition('events', [
      TutorialStep('events.scope', 'Find events',
          'See events from your church or discover public events from other churches.'),
      TutorialStep('events.card', 'Event details',
          'Open an event for its time, location, RSVP and reminder options.'),
      TutorialStep('events.create', 'Create an event',
          'Your role lets you propose or publish events from here.'),
    ]),
    'bible.home': const TutorialDefinition('bible.home', [
      TutorialStep('bible.read', 'Read Scripture',
          'Choose a book and chapter to start reading.'),
      TutorialStep('bible.search', 'Find a passage',
          'Search for verses without browsing every book.'),
      TutorialStep('bible.quiz', 'Daily quiz',
          'Read the suggested passage, take the quiz and see your progress.'),
    ]),
    'more': const TutorialDefinition('more', [
      TutorialStep('more.features', 'More to explore',
          'Find church tools, conversations and features available to your account.'),
      TutorialStep('more.settings', 'Your settings',
          'Manage privacy, notifications, app preferences and guided tutorials here.'),
    ]),
    for (final role in [
      'member',
      'pastor',
      'admin',
      'finance',
      'ministry_leader',
      'care',
      'service',
      'ministry_worker',
      'unconnected'
    ])
      'dashboard.$role': TutorialDefinition('dashboard.$role', [
        TutorialStep(
            'dashboard.welcome',
            switch (role) {
              'pastor' => 'Pastor tools',
              'admin' => 'Church overview',
              'finance' => 'Finance overview',
              'care' => 'Member care',
              'service' => 'Your service team',
              'unconnected' => 'Welcome to Grace',
              'ministry_leader' => 'Ministry leadership',
              'ministry_worker' => 'Your ministry',
              _ => 'Welcome home',
            },
            role == 'unconnected'
                ? 'Explore the global community. Connect with a church whenever you are ready.'
                : 'Your home brings together the updates and tools available to your role.'),
        const TutorialStep('dashboard.actions', 'Quick access',
            'Your most useful tools are grouped here. Choose one whenever you need it.'),
        if (role == 'pastor')
          const TutorialStep('dashboard.care', 'Care for your community',
              'Open prayer requests and respond using the care tools available to your role.'),
        const TutorialStep('dashboard.word', 'Daily encouragement',
            'Take a moment for today’s reflection and its Scripture reference.'),
        const TutorialStep('dashboard.church', 'Your church',
            'Keep up with upcoming services and your church community.'),
      ]),
    ..._secondary,
  };
  static final Map<String, TutorialDefinition> _secondary = {
    for (final row in const <List<String>>[
      [
        'members',
        'Your church directory',
        'Find members and open a profile to learn more or get in touch.',
        'Find someone',
        'Use the search and filters to narrow the directory.'
      ],
      [
        'inbox',
        'Your conversations',
        'Open a conversation to read messages, photos and shared posts.',
        'Start a conversation',
        'Choose someone to message using the new-conversation control.'
      ],
      [
        'attendance',
        'Your attendance',
        'See your service records and whether you arrived early, on time or late.',
        'Check-in options',
        'Review automatic check-in readiness, or use manual sign-in for the current service.'
      ],
      [
        'church_transfer',
        'Church connection',
        'Review your current church and request a transfer when you are ready.',
        'Choose a church',
        'Search for the church you would like to join.'
      ],
      [
        'announcements',
        'Church announcements',
        'Read the latest notices from your church in one place.',
        'Share an announcement',
        'Your role allows you to create a notice here.'
      ],
      [
        'schedule_management',
        'Service schedules',
        'Manage when church services take place and the timezone they use.',
        'Add a service',
        'Create a schedule for a service your church regularly holds.'
      ],
      [
        'testimonies',
        'Stories of faith',
        'Read testimonies from the global community or your church.',
        'Share your testimony',
        'Choose the audience when you share an encouragement of your own.'
      ],
      [
        'ministries',
        'Church ministries',
        'Explore ministry teams and the ways you can take part.',
        'Manage a ministry',
        'The controls shown here depend on your ministry responsibilities.'
      ],
      [
        'prayers',
        'Prayer and care',
        'Share a request or find prayers available to you and your care team.',
        'Share a request',
        'Choose who can see your prayer before sending it.'
      ],
      [
        'prayers.staff',
        'Prayer care',
        'Review prayer requests assigned or available to your care role.',
        'Your care work',
        'Open a request to review its details and available care actions.'
      ],
      [
        'counseling.staff',
        'Pastoral care requests',
        'Review counseling requests available to your role.',
        'Support your community',
        'Open a request to review and follow up with the care team.'
      ],
      [
        'counseling',
        'A place for support',
        'Request a conversation with your church’s care team and review your requests.',
        'Request support',
        'Start a private request when you would like someone to talk with.'
      ],
      [
        'live_streaming',
        'Watch together',
        'Find a live service or open a stream to join your community.',
        'Stream details',
        'Open a service to watch and see the information shared by its church.'
      ],
      [
        'analytics',
        'Church insights',
        'See church activity and trends available to your role.',
        'Explore the results',
        'Open a result to explore the information behind it.'
      ],
      [
        'donations',
        'Your giving',
        'Review giving information and the options provided by your church.',
        'Giving options',
        'Read the details before choosing an option. This guide never starts a payment.'
      ],
      [
        'notifications',
        'Stay up to date',
        'Open a notification to go to the post, message or service it refers to.',
        'Open an update',
        'Tap an update to return to the conversation, post or service it refers to.'
      ],
      [
        'grace_rooms',
        'Grace Rooms',
        'Find a room for conversation, prayer or a shared interest.',
        'Join a conversation',
        'Open a room to read and send messages with its members.'
      ],
      [
        'saved_items',
        'Keep it close',
        'Your saved posts and events stay together here for easy reference.',
        'Open something saved',
        'Choose an item to return to its original content.'
      ],
      [
        'public_profile',
        'Your public profile',
        'See the profile and public content a person shares with the community.',
        'Posts and reels',
        'Explore the content this person has shared with you.'
      ],
      [
        'profile',
        'Your account',
        'Review your profile and church connection here.',
        'Make it yours',
        'Edit the details you want to share with your community.'
      ],
      [
        'settings',
        'Your preferences',
        'Manage your account, church life and app preferences in one place.',
        'Devices and app',
        'Change appearance and feedback, or restart guided tutorials here.'
      ],
      [
        'devices_app',
        'Make it comfortable',
        'Choose your theme, data-saving and haptic preferences.',
        'Guided tutorials',
        'Turn guidance off or restart it whenever you want a fresh look around.'
      ],
      [
        'role_management',
        'Roles and access',
        'Review responsibilities and assign only the access each person needs.',
        'Find a member',
        'Choose a member to review the roles available for their responsibilities.'
      ],
      [
        'finance',
        'Church finance',
        'Review the financial information your role permits you to see.',
        'Financial records',
        'Use the available controls to explore records and reports.'
      ],
      [
        'live_management',
        'Manage live services',
        'Set up the stream information your church shares with members.',
        'Stream settings',
        'Review the connection and service details before going live.'
      ],
      [
        'church_administration',
        'Your church profile',
        'Keep your church’s information and branding up to date.',
        'Administration tools',
        'Open the management tools available to your church role.'
      ],
    ])
      row[0]: TutorialDefinition(row[0], [
        TutorialStep('${row[0]}.overview', row[1], row[2]),
        TutorialStep('${row[0]}.tools', row[3], row[4]),
      ]),
  };
}
