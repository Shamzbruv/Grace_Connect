class ChurchRole {
  final String id;
  final String name;
  final String category;
  final String description;
  final List<String> responsibilities;
  final List<String> platformDuties;

  const ChurchRole({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.responsibilities,
    required this.platformDuties,
  });
}

// --- CATEGORIES ---
const String catGovernance = 'Governance';
const String catService = 'Service';
const String catWorshipMedia = 'Worship & Media';
const String catTeaching = 'Teaching & Discipleship';
const String catPrayerCare = 'Prayer & Care';
const String catMinistries = 'Ministries';
const String catMembership = 'Membership';

// --- REGISTRY ---
const List<ChurchRole> churchRoleRegistry = [
  // A) GOVERNANCE
  ChurchRole(
    id: 'senior_pastor',
    name: 'Senior Pastor',
    category: catGovernance,
    description: 'Spiritual head + overall governance',
    responsibilities: [
      'Oversees doctrine, preaching, direction, discipline',
      'Approves church-wide announcements/events',
      'Final approval for leadership appointments'
    ],
    platformDuties: [
      'Approve/deny high-impact events',
      'View church analytics dashboards',
      'Assign or revoke leadership roles'
    ],
  ),
  ChurchRole(
    id: 'pastor',
    name: 'Pastor',
    category: catGovernance,
    description: 'Spiritual leadership + ministry oversight',
    responsibilities: [
      'Oversees assigned ministries / districts',
      'Counseling, visitation, teaching'
    ],
    platformDuties: [
      'Manage events/posts for assigned ministries',
      'Assign follow-ups',
      'Moderate ministry discussions'
    ],
  ),
  ChurchRole(
    id: 'assistant_pastor',
    name: 'Assistant Pastor',
    category: catGovernance,
    description: 'Assists with spiritual leadership',
    responsibilities: ['Supports pastoral team'],
    platformDuties: ['Manage events', 'Assign follow-ups'],
  ),
  ChurchRole(
    id: 'acting_pastor',
    name: 'Acting Pastor',
    category: catGovernance,
    description: 'Interim spiritual leadership',
    responsibilities: ['Interim oversight'],
    platformDuties: ['Manage events', 'View analytics'],
  ),
  ChurchRole(
    id: 'elder',
    name: 'Elder',
    category: catGovernance,
    description: 'Spiritual governance + discipline',
    responsibilities: ['Supports pastoral leadership', 'Member care'],
    platformDuties: ['Access care notes', 'Lead mentorship groups'],
  ),
  ChurchRole(
    id: 'deacon',
    name: 'Deacon',
    category: catGovernance,
    description: 'Operational support + service order',
    responsibilities: ['Maintains order', 'Supports communion'],
    platformDuties: ['Manage service schedules', 'Log service readiness'],
  ),
  ChurchRole(
    id: 'deaconess',
    name: 'Deaconess',
    category: catGovernance,
    description: 'Member care + support for women/families',
    responsibilities: ['Supports women/families', 'Baptism prep'],
    platformDuties: ['Manage care tasks', 'Track outreach'],
  ),
  ChurchRole(
    id: 'church_secretary',
    name: 'Church Secretary',
    category: catGovernance,
    description: 'Records, communications, administration',
    responsibilities: ['Membership records', 'Meeting minutes'],
    platformDuties: ['Manage member directory fields', 'Post official notices'],
  ),
  ChurchRole(
    id: 'treasurer',
    name: 'Treasurer',
    category: catGovernance,
    description: 'Oversight of finances',
    responsibilities: ['Oversees accounting', 'Authorizes expenses'],
    platformDuties: ['View financial dashboard', 'Export finance reports'],
  ),
  ChurchRole(
    id: 'financial_secretary',
    name: 'Financial Secretary',
    category: catGovernance,
    description: 'Offerings tracking + reporting',
    responsibilities: ['Records offerings', 'Reconciles records'],
    platformDuties: ['Enter giving records', 'Generate receipts'],
  ),
  ChurchRole(
    id: 'trustee_property_steward',
    name: 'Trustee / Property Steward',
    category: catGovernance,
    description: 'Property + assets oversight',
    responsibilities: ['Building maintenance', 'Vendor coordination'],
    platformDuties: ['Maintenance requests', 'Asset inventory'],
  ),

  // B) SERVICE & EXPERIENCE
  ChurchRole(
    id: 'head_usher',
    name: 'Head Usher',
    category: catService,
    description: 'Service flow + ushers management',
    responsibilities: ['Organizes seating', 'Crowd management'],
    platformDuties: ['Build usher schedules', 'Check-in tasks'],
  ),
  ChurchRole(
    id: 'usher',
    name: 'Usher',
    category: catService,
    description: 'Welcome, seating, order',
    responsibilities: ['Greets members', 'Guides seating'],
    platformDuties: ['View schedule', 'Submit reports'],
  ),
  ChurchRole(
    id: 'hospitality_coordinator',
    name: 'Hospitality Coordinator',
    category: catService,
    description: 'Guest welcome + refreshments',
    responsibilities: ['Coordinates guest reception'],
    platformDuties: ['Manage guest follow-ups', 'Maintain roster'],
  ),
  ChurchRole(
    id: 'security_coordinator',
    name: 'Security Coordinator',
    category: catService,
    description: 'Safety and order',
    responsibilities: ['Oversees security team'],
    platformDuties: ['Access incident module', 'Manage roster'],
  ),

  // C) WORSHIP & MEDIA
  ChurchRole(
    id: 'worship_leader',
    name: 'Worship Leader',
    category: catWorshipMedia,
    description: 'Worship planning + leading',
    responsibilities: ['Plans worship sets', 'Coordinates musicians'],
    platformDuties: ['Create worship schedules', 'Share setlists'],
  ),
  ChurchRole(
    id: 'choir_director',
    name: 'Choir Director',
    category: catWorshipMedia,
    description: 'Choir training + performance',
    responsibilities: ['Oversees rehearsals', 'Song selection'],
    platformDuties: ['Manage choir roster', 'Schedule rehearsals'],
  ),
  ChurchRole(
    id: 'musician',
    name: 'Musician',
    category: catWorshipMedia,
    description: 'Musical support',
    responsibilities: ['Musical performance'],
    platformDuties: ['View schedules', 'Confirm availability'],
  ),
  ChurchRole(
    id: 'media_av_director',
    name: 'Media/AV Director',
    category: catWorshipMedia,
    description: 'Livestream, sound, projection',
    responsibilities: ['Coordinates AV team', 'Technical readiness'],
    platformDuties: ['Manage service production', 'Manage media schedules'],
  ),
  ChurchRole(
    id: 'media_team_member',
    name: 'Media Team Member',
    category: catWorshipMedia,
    description: 'Operate equipment',
    responsibilities: ['Operate cameras/sound'],
    platformDuties: ['Upload clips', 'Run checklists'],
  ),

  // D) TEACHING & DISCIPLESHIP
  ChurchRole(
    id: 'sunday_school_superintendent',
    name: 'Sunday School Supt.',
    category: catTeaching,
    description: 'Department leader',
    responsibilities: ['Coordinates teachers', 'Curriculum'],
    platformDuties: ['Create classes', 'Assign teachers'],
  ),
  ChurchRole(
    id: 'sunday_school_teacher',
    name: 'Sunday School Teacher',
    category: catTeaching,
    description: 'Teaching + class care',
    responsibilities: ['Teach lessons', 'Student care'],
    platformDuties: ['Post class resources', 'Manage attendance'],
  ),
  ChurchRole(
    id: 'bible_study_leader',
    name: 'Bible Study Leader',
    category: catTeaching,
    description: 'Midweek teaching leader',
    responsibilities: ['Lead discussions'],
    platformDuties: ['Create sessions', 'Post notes'],
  ),

  // E) PRAYER & CARE
  ChurchRole(
    id: 'prayer_ministry_leader',
    name: 'Prayer Ministry Leader',
    category: catPrayerCare,
    description: 'Oversees prayer operations',
    responsibilities: ['Coordinates prayer team'],
    platformDuties: ['Assign requests', 'Access sensitive prayers'],
  ),
  ChurchRole(
    id: 'intercessor',
    name: 'Prayer Team / Intercessor',
    category: catPrayerCare,
    description: 'Prayer request execution',
    responsibilities: ['Pray for requests'],
    platformDuties: ['Receive assignments', 'Update status'],
  ),
  ChurchRole(
    id: 'care_counseling_coordinator',
    name: 'Care & Counseling Coord.',
    category: catPrayerCare,
    description: 'Member care coordination',
    responsibilities: ['Coordinate counseling', 'Care needs'],
    platformDuties: ['Assign care cases', 'Manage follow-ups'],
  ),

  // F) MINISTRIES
  ChurchRole(
    id: 'youth_ministry_leader',
    name: 'Youth Ministry Leader',
    category: catMinistries,
    description: 'Youth oversight',
    responsibilities: ['Youth events', 'Discipleship'],
    platformDuties: ['Youth events', 'Volunteer assignment'],
  ),
  ChurchRole(
    id: 'teen_ministry_leader',
    name: 'Teen Ministry Leader',
    category: catMinistries,
    description: 'Teen oversight',
    responsibilities: ['Teen events', 'Mentorship'],
    platformDuties: ['Teen events', 'Check-ins'],
  ),
  ChurchRole(
    id: 'life_builders_ministry_leader',
    name: 'Life Builders Leader',
    category: catMinistries,
    description: 'Development ministry leader',
    responsibilities: ['Groups oversight'],
    platformDuties: ['Manage groups', 'Post resources'],
  ),
  ChurchRole(
    id: 'mens_ministry_leader',
    name: 'Men\'s Ministry Leader',
    category: catMinistries,
    description: 'Men\'s ministry oversight',
    responsibilities: ['Men\'s events'],
    platformDuties: ['Events', 'Engagement'],
  ),
  ChurchRole(
    id: 'womens_ministry_leader',
    name: 'Women\'s Ministry Leader',
    category: catMinistries,
    description: 'Women\'s ministry oversight',
    responsibilities: ['Women\'s events'],
    platformDuties: ['Events', 'Support workflows'],
  ),
  ChurchRole(
    id: 'childrens_ministry_leader',
    name: 'Children\'s Leader',
    category: catMinistries,
    description: 'Children\'s oversight',
    responsibilities: ['Children\'s events'],
    platformDuties: ['Events', 'Safety workflows'],
  ),

  // G) MEMBERSHIP
  ChurchRole(
    id: 'member',
    name: 'Member',
    category: catMembership,
    description: 'Regular church member',
    responsibilities: ['Attend services', 'Participate'],
    platformDuties: ['View content', 'Submit requests'],
  ),
  ChurchRole(
    id: 'visitor',
    name: 'Visitor',
    category: catMembership,
    description: 'Guest / Visitor',
    responsibilities: ['Visit services'],
    platformDuties: ['Read-only content', 'Request follow-up'],
  ),
];
