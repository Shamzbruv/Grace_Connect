
path = 'lib/screens/community/community_feed_screen.dart'
try:
    with open(path, 'r') as f:
        content = f.read()
    
    # 1. Update Provider access to get userProfile
    if 'final userRole = Provider.of<UserRoleProvider>(context).role;' in content:
        content = content.replace(
            'final userRole = Provider.of<UserRoleProvider>(context).role;', 
            'final userProvider = Provider.of<UserRoleProvider>(context);\\n    final churchId = userProvider.userProfile?.placeId ?? "";'
        )
    
    # 2. Update getPosts call
    if '_communityService.getPosts(),' in content:
        content = content.replace('_communityService.getPosts(),', '_communityService.getPosts(churchId),')
    elif '_communityService.getPosts()' in content:
        # Handle case without comma if formatted differently
        content = content.replace('_communityService.getPosts()', '_communityService.getPosts(churchId)')
        
    with open(path, 'w') as f:
        f.write(content)
    print(f"Fixed {path}")
except Exception as e:
    print(f"Error accessing {path}: {e}")
