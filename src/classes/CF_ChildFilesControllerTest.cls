/**
 * Developed by Doug Ayers (douglascayers.com)
 */
@IsTest
private class CF_ChildFilesControllerTest {

    @IsTest
    static void test_get_related_files() {

        Account acct = new Account(
            name = 'Test Account'
        );

        insert acct;

        Contact cont = new Contact(
            firstName = 'Test',
            lastName = 'Contact',
            accountId = acct.id
        );

        insert cont;

        List<Map<String, Object>> relatedFiles = null;

        Test.startTest();

        relatedFiles = CF_ChildFilesController.getRelatedFiles( 'Contact', 'AccountId', acct.id );
        System.assertEquals( 0, relatedFiles.size() );

        ContentVersion newFile1 = new ContentVersion(
            title = 'Test File',
            pathOnClient = 'Test File.txt',
            versionData = Blob.valueOf( 'Test' ),
            firstPublishLocationId = cont.id
        );

        ContentVersion newFile2 = new ContentVersion(
            title = 'Test File 2',
            pathOnClient = 'Test File 2.txt',
            versionData = Blob.valueOf( 'Test 2' ),
            firstPublishLocationId = cont.id
        );

        insert new ContentVersion[] { newFile1, newFile2 };

        relatedFiles = CF_ChildFilesController.getRelatedFiles( 'Contact', 'AccountId', acct.id );
        System.assertEquals( 2, relatedFiles.size() );

        Test.stopTest();

    }

    @IsTest
    static void test_get_object_describe() {

        Test.startTest();

        Map<String, Object> objectDescribeMap = CF_ChildFilesController.getObjectDescribe( 'Account' );

        Test.stopTest();

        DescribeSObjectResult objectDescribe = Account.sobjectType.getDescribe();

        System.assertEquals( objectDescribeMap.get('name'), objectDescribe.getName() );

    }

}