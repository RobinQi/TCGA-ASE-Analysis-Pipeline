#!/usr/bin/perl -w

use MCE;
use strict;
use FindBin qw($Bin);
use lib "$Bin/..";
use Parsing_Routines;
use Dwnld_WGS_RNA;
use File::Copy;
use Getopt::Long;
use autodie;
use Cwd 'realpath';
use File::Basename;

my $time = localtime;
print "Script started on $time.\n";

#Changes to the directory of the script executing;
chdir $Bin;

my $parsing = TCGA_Lib::Parsing_Routines->new;
my $dwnld = TCGA_Lib::Dwnld_WGS_RNA->new;

GetOptions(
    'disease|d=s' => \my $disease_abbr,#e.g. OV
    'exp_strat|e=s' => \my $Exp_Strategy,#e.g. Genotyping array
    'array_type|a=s' =>\my $array_type,#e.g Genotypes
    'key|k=s' => \my $key,
    'help|h' => \my $help
) or die "Incorrect options!\n",$parsing->usage("0");

if ($help)
{
    $parsing->usage("0");
}

my $TCGA_Pipeline_Dir = realpath("../../");
mkdir "$TCGA_Pipeline_Dir/Analysis" unless(-d "$TCGA_Pipeline_Dir/Analysis");
my $Analysispath = realpath("../../Analysis");
my $SNP = "SNP6";
my $tables = "$disease_abbr\_tables";

if (!defined $disease_abbr || !defined $Exp_Strategy || !defined $array_type)
{
    print "disease type, experimental strategy and/or array type was not entered!\n";
    $parsing->usage("0");
}

if ("$Exp_Strategy" eq "Genotyping array")
{
    if("$array_type" ne "Genotypes" and "$array_type" ne "Copy number estimate")
    {
        print STDERR "data type must be Genotypes or Copy number estimate as those are the types that are used in this pipeline.\n";
        $parsing->usage("0");
    }
}
else
{
    print "The experimental strategy that was entered in was not the right one, it should be Genotyping array for this script.\n";
    $parsing->usage("0");
}

if (!defined $key or (!(-f $key)))
{
    print "gdc key fullpath was not entered or the fullpath to it was not correct!\n";
    print $key,"\n";
    $parsing->usage("0");
}

#Check if the Database directory does not exist
if(!(-d "$TCGA_Pipeline_Dir/Database"))
{
    print STDERR "$TCGA_Pipeline_Dir/Database does not exist, it was either moved, renamed, deleted or has not been downloaded.\nPlease check the README.md file on the github page to find out where to get the Database directory.\n";
    exit;
}

`mkdir -p "$Analysispath/$disease_abbr/$SNP"` unless(-d "$Analysispath/$disease_abbr/$SNP");        
my $OUT_DIR = "$Analysispath/$disease_abbr/$SNP/$array_type";

`mkdir -p "$OUT_DIR"`;

my $SNP_dir = dirname("$OUT_DIR");

chdir "$SNP_dir" or die "Can't change to directory $SNP_dir: $!\n";

#Check gdc key and mv it to db first!
#copyfile2newfullpath(path to gdc key file,path where gdc key file will be copied)
$parsing->copyfile2newfullpath("$key","$SNP_dir/gdc.key");

if(!(-f "$Analysispath/$disease_abbr/$tables/$disease_abbr.$array_type.id2uuid.txt"))
{
    #gets the manifest file from gdc and gets the UUIDs from it
    #gdc_parser(cancer type(e.g. OV),type of data (Genotypign array),data type)
    $dwnld->gdc_parser($disease_abbr,"$Exp_Strategy","$array_type");
    
    if ("$array_type" eq "Copy number estimate")
    {
        open(my $tangent,"$disease_abbr.$array_type.result.txt") or die "Can't open file for input: $!\n";
        open(my $out,">$disease_abbr\_tangent.txt") or die "Can't open file for output: $!\n";
        my @tanarray = <$tangent>;
        chomp(@tanarray);
        close ($tangent);
        @tanarray = grep{/tangent/}@tanarray;
        foreach(@tanarray)
        {
            print $out "$_\n";
        }
        close($out);
        #puts the UUIDs in a payload file which will be used for the curl command
        #metadata_collect(tangent.txt file,output file)
        $dwnld->metadata_collect("$disease_abbr\_tangent.txt","$disease_abbr\_$array_type\_Payload.txt");
    }
    #This filter only gets birdseed files. This is mainly for cancer types that have files that are not just birdseed
    elsif($array_type eq "Genotypes")
    {
        open(my $birdseed,"$disease_abbr.$array_type.result.txt") or die "Can't open $disease_abbr.$array_type.result.txt for input: $!\n";
        open(my $out,">$disease_abbr\_birdseed.txt") or die "Can't open file for output: $!\n";
        my @birdseedarray = <$birdseed>;
        chomp(@birdseedarray);
        close ($birdseed);
        @birdseedarray = grep{/birdseed/}@birdseedarray;
        foreach(@birdseedarray)
        {
            print $out "$_\n";
        }
        close($out);
        #metadata_collect(birdseed.txt file,output file)
        $dwnld->metadata_collect("$disease_abbr\_birdseed.txt","$disease_abbr\_$array_type\_Payload.txt");
    }
    
    `curl --request POST --header \'Content-Type: application/json\' --data \@\'$disease_abbr\_$array_type\_Payload.txt\' \'https://gdc-api.nci.nih.gov/legacy/files\' > \'$disease_abbr\_$array_type.metadata.txt\'`;
    
    #matches UUID and TCGA ID
    #The columns of each cancer type may be different
    #QueryBase(.result.txt file from gdc_parser,query column,.metadata.txt file from the curl command,reqular expression,output file,column(s) to keep)
    $parsing->QueryBase("$disease_abbr.$array_type.result.txt",1,"$disease_abbr\_$array_type.metadata.txt",'TCGA-\w+-\w+-\w+',"t1.txt",0);
    $parsing->QueryBase("t1.txt",1,"$disease_abbr\_$array_type.metadata.txt",'(tumor|blood|normal)',"$disease_abbr.$array_type.id2uuid_query.txt",1);
    
    open(IDI,"$disease_abbr.$array_type.id2uuid_query.txt") or die "Can't open file $disease_abbr.$array_type.id2uuid_query.txt: $!\n";
    open(IDO,">$disease_abbr.$array_type.id2uuid.txt") or die "Can't open file $disease_abbr.$array_type.id2uuid.txt: $!\n";
    
    while(my $r = <IDI>)
    {
	chomp($r);
	my @a = split("\t",$r);
	my $TCGA = $a[1];
	$TCGA =~ s/-\d\d\D+//;
	print IDO "$r\t$TCGA\n";
    }
    close(IDI);
    close(IDO);
    
    #downloads files from gdc
    #download_files_from_gdc(download file,gdc key file directory,output directory,data type(e.g. Genotypes))
    $dwnld->download_files_from_gdc("$disease_abbr.$array_type.id2uuid.txt","$SNP_dir","$OUT_DIR","$array_type"); 
    
    `mkdir $Analysispath/$disease_abbr/$tables` unless(-d "$Analysispath/$disease_abbr/$tables");
    
    copy("$disease_abbr.$array_type.id2uuid.txt","$Analysispath/$disease_abbr/$tables");
}
else
    {
        print "It seems that a table already exists in $Analysispath/$disease_abbr/$tables: $disease_abbr.$array_type.id2uuid.txt\n";
        $dwnld->download_files_from_gdc("$Analysispath/$disease_abbr/$tables/$disease_abbr.$array_type.id2uuid.txt","$SNP_dir","$OUT_DIR","$array_type"); 
    }
#get_only_files_in_dir(directory to get files from)
my @del_files = $parsing->get_only_files_in_dir("$SNP_dir");

for(my $i = 0;$i < scalar(@del_files);$i++)
{
    `rm "$del_files[$i]"`;
}

print "All jobs have finished for $disease_abbr.\n";

$time = localtime;
print "Script finished on $time.\n";

exit;
