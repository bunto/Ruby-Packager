#--
# Copyright (c) 2009 Muriel Salvan (murielsalvan@users.sourceforge.net)
# Licensed under the terms specified in LICENSE file. No warranty is provided.
#++

# Release a distribution of a Ruby program.
# This produces an installable executable that will install a set of files and directories:
# * A binary, including some core Ruby and program files (eventually the whole Ruby distribution if needed - that is if the program is meant to be run on platforms not providing Ruby)
# * A list of files/directories

require 'fileutils'

module RubyPackager

  # Copy a list of files patterns to the release directory
  #
  # Parameters:
  # * *iRootDir* (_String_): The root dir
  # * *iReleaseDir* (_String_): The release dir
  # * *iFilesPatterns* (<em>list<String></em>): The list of files patterns
  def self.copyFiles(iRootDir, iReleaseDir, iFilesPatterns)
    iFilesPatterns.each do |iFilePattern|
      Dir.glob(File.expand_path(iFilePattern)).each do |iFileName|
        if (File.basename(iFileName).match(/^(\.svn|CVS)$/) == nil)
          lRelativeName = nil
          # Extract the relative file name
          lMatch = iFileName.match(/^#{iRootDir}\/(.*)$/)
          if (lMatch == nil)
            # The path is already relative
            lRelativeName = iFileName
          else
            lRelativeName = lMatch[1]
          end
          lDestFileName = "#{iReleaseDir}/#{lRelativeName}"
          FileUtils::mkdir_p(File.dirname(lDestFileName))
          if (File.directory?(iFileName))
            puts "Create directory #{lRelativeName}"
          else
            puts "Copy file #{lRelativeName}"
            FileUtils::cp(iFileName, lDestFileName)
          end
        end
      end
    end
  end

  # Class that makes a release
  class Releaser

    # Constructor
    #
    # Parameters:
    # * *iPluginsManager* (<em>RUtilAnts::Plugins::PluginsManager</em>): The Plugins manager
    # * *iReleaseInfo* (_ReleaseInfo_): The release information
    # * *iRootDir* (_String_): The root directory, containing files to ship in the distribution
    # * *iReleaseBaseDir* (_String_): The release directory, where files will be copied and generated for distribution
    # * *iPlatformReleaseInfo* (_Object_): The platform dependent release info
    # * *iReleaseVersion* (_String_): Version to release
    # * *iReleaseTags* (<em>list<String></em>): Tags associated to this release
    # * *iReleaseComment* (_String_): Comment accompanying this release
    # * *iIncludeRuby* (_Boolean_): Do we include Ruby in the release ?
    # * *iIncludeTest* (_Boolean_): Do we include test files in the release ?
    # * *iInstallers* (<em>list<String></em>): The list of installers to generate
    # * *iDistributors* (<em>list<String></em>): The list of distributors to ship installers to
    def initialize(iPluginsManager, iReleaseInfo, iRootDir, iReleaseBaseDir, iPlatformReleaseInfo, iReleaseVersion, iReleaseTags, iReleaseComment, iIncludeRuby, iIncludeTest, iInstallers, iDistributors)
      @PluginsManager, @ReleaseInfo, @RootDir, @ReleaseBaseDir, @PlatformReleaseInfo, @ReleaseVersion, @ReleaseTags, @ReleaseComment, @IncludeRuby, @IncludeTest, @Installers, @Distributors = iPluginsManager, iReleaseInfo, iRootDir, iReleaseBaseDir, iPlatformReleaseInfo, iReleaseVersion, iReleaseTags, iReleaseComment, iIncludeRuby, iIncludeTest, iInstallers, iDistributors
      @GemName = "#{@ReleaseInfo.GemInfo[:GemName]}-#{@ReleaseVersion}.gem"
      # Compute the release directory name
      lStrOptions = 'Normal'
      if (@IncludeRuby)
        if (@IncludeTest)
          lStrOptions = 'IncludeRuby_IncludeTest'
        else
          lStrOptions = 'IncludeRuby'
        end
      elsif (@IncludeTest)
        lStrOptions = 'IncludeTest'
      end
      @ReleaseDir = "#{@ReleaseBaseDir}/#{RUBY_PLATFORM}/#{@ReleaseVersion}/#{lStrOptions}/#{Time.now.strftime('%Y_%m_%d_%H_%M_%S')}"
      @InstallerDir = "#{@ReleaseDir}/Installer"
      @DocDir = "#{@ReleaseDir}/Documentation"
      @ReleaseDir += '/Release'
    end

    # Release
    #
    # Return:
    # * _Boolean_: Success ?
    def execute
      rSuccess = true

      # First check that every tool we will need is present
      # TODO: Use RDI to install missing ones
      logOp('Check installed tools') do
        # Check that the tools we need to release are indeed here
        if ((@ReleaseInfo.respond_to?(:checkReadyForRelease)) and
            (!@ReleaseInfo.checkReadyForRelease(@RootDir)))
          rSuccess = false
        end
        if (@ReleaseInfo.ExecutableInfo[:StartupRBFile] != nil)
          # Check tools for platform dependent considerations
          if (!@PlatformReleaseInfo.checkExeTools(@RootDir, @IncludeRuby))
            rSuccess = false
          end
        end
        @Installers.each do |iInstallerName|
          @PluginsManager.accessPlugin('Installers', iInstallerName) do |ioPlugin|
            if (!ioPlugin.checkTools)
              rSuccess = false
            end
          end
        end
        @Distributors.each do |iDistributorName|
          @PluginsManager.accessPlugin('Distributors', iDistributorName) do |ioPlugin|
            if (!ioPlugin.checkTools)
              rSuccess = false
            end
          end
        end
      end
      if (rSuccess)
        # Release files and create binary if needed
        rSuccess = releaseFiles
        if (rSuccess)
          # Generate documentation
          rSuccess = generateRDoc
          if (rSuccess)
            # Generate Release notes
            rSuccess = generateReleaseNote_HTML
            if (rSuccess)
              rSuccess = generateReleaseNote_TXT
              if (rSuccess)
                # Create installers
                # List of files generated to distribute
                # list< String >
                lGeneratedInstallers = []
                if (!@Installers.empty?)
                  FileUtils::mkdir_p(@InstallerDir)
                end
                @Installers.each do |iInstallerName|
                  logOp("Create installer #{iInstallerName}") do
                    @PluginsManager.accessPlugin('Installers', iInstallerName) do |ioPlugin|
                      lFileName = ioPlugin.createInstaller(@RootDir, @ReleaseDir, @InstallerDir, @ReleaseVersion, @ReleaseInfo)
                      if (lFileName == nil)
                        rSuccess = false
                      else
                        lGeneratedInstallers << lFileName
                      end
                    end
                  end
                end
                if (rSuccess)
                  # 5. Distribute
                  @Distributors.each do |iDistributorName|
                    logOp("Distribute to #{iDistributorName}") do
                      @PluginsManager.accessPlugin('Distributors', iDistributorName) do |ioPlugin|
                        if (!ioPlugin.distribute(@InstallerDir, @ReleaseVersion, @ReleaseInfo, lGeneratedInstallers, @DocDir))
                          rSuccess = false
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      return rSuccess
    end

    private

    # Log an operation, and call some code inside
    #
    # Parameters:
    # * *iOperationName* (_String_): Operation name
    # * *CodeBlock*: Code to call in this operation
    def logOp(iOperationName)
      puts "===== #{iOperationName} ..."
      yield
      puts "===== ... #{iOperationName}"
    end

    # Release files in a directory, and create the executable if needed
    #
    # Return:
    # * _Boolean_: Success ?
    def releaseFiles
      rSuccess = true

      logOp('Copy core files') do
        RubyPackager::copyFiles(@RootDir, @ReleaseDir, @ReleaseInfo.CoreFiles)
        # Create the ReleaseVersion file
        lStrTags = nil
        if (@ReleaseTags.empty?)
          lStrTags = ':Tags => []'
        else
          lStrTags = ":Tags => [ '#{@ReleaseTags.join('\' \'')}' ]"
        end
        File.open("#{@ReleaseDir}/ReleaseInfo", 'w') do |oFile|
          oFile << "
# This file has been generated by RubyPackager during a delivery.
# More info about RubyPackager: http://rubypackager.sourceforge.net
{
  :Version => '#{@ReleaseVersion}',
  #{lStrTags},
  :DevStatus => '#{@ReleaseInfo.ProjectInfo[:DevStatus]}'
}
"
        end
      end
      if (@ReleaseInfo.ExecutableInfo[:StartupRBFile] != nil)
        logOp('Create binary') do
          # TODO (crate): When crate will work correctly under Windows, use it here to pack everything
          # For now the executable creation is platform dependent
          rSuccess = @PlatformReleaseInfo.createBinary(@RootDir, @ReleaseDir, @IncludeRuby, @ReleaseInfo)
        end
      end
      if (rSuccess)
        logOp('Copy additional files') do
          RubyPackager::copyFiles(@RootDir, @ReleaseDir, @ReleaseInfo.AdditionalFiles)
        end
        logOp('Copy test files') do
          RubyPackager::copyFiles(@RootDir, @ReleaseDir, @ReleaseInfo.TestFiles)
        end
      end

      return rSuccess
    end

    # Generate rdoc
    #
    # Return:
    # * _Boolean_: Success ?
    def generateRDoc
      rSuccess = true

      puts "==== Generating RDoc ..."
      $ProjectInfo = {
        :Name => @ReleaseInfo.ProjectInfo[:Name],
        :Version => @ReleaseVersion,
        :Tags => @ReleaseTags,
        :DevStatus => @ReleaseInfo.ProjectInfo[:DevStatus],
        :Author => @ReleaseInfo.AuthorInfo[:Name],
        :AuthorMail => @ReleaseInfo.AuthorInfo[:EMail],
        :AuthorURL => @ReleaseInfo.AuthorInfo[:WebPageURL],
        :HomepageURL => @ReleaseInfo.ProjectInfo[:WebPageURL],
        :ImageURL => @ReleaseInfo.ProjectInfo[:ImageURL],
        # TODO: Do not hardcode SF anymore
        :DownloadURL => "https://sourceforge.net/projects/#{@ReleaseInfo.SFInfo[:ProjectUnixName]}/files/#{@ReleaseVersion}/#{@GemName}/download",
        :SVNBrowseURL => @ReleaseInfo.ProjectInfo[:SVNBrowseURL],
        :FaviconURL => @ReleaseInfo.ProjectInfo[:FaviconURL],
        :RootDir => @RootDir
      }
      gem 'rdoc'
      require 'rdoc/rdoc'
      lOldDir = Dir.getwd
      Dir.chdir(@ReleaseDir)
      RDoc::RDoc.new.document( [
        '--line-numbers',
        '--tab-width=2',
        "--title=#{@ReleaseInfo.ProjectInfo[:Name].gsub(/'/,'\\\\\'')} v#{@ReleaseVersion}",
        '--fileboxes',
        '--fmt=darkfish',
        '--exclude=.svn',
        '--exclude=nbproject',
        '--exclude=Done.txt',
        "--exclude=Releases",
        "--output=#{@DocDir}/rdoc"
        # Bug (RDoc): Sometimes it does not change current directory correctly (not deterministic)
      ] )
      Dir.chdir(lOldDir)

      return rSuccess
    end

    # Generate a release note file to attach to this release
    #
    # Return:
    # * _Boolean_: Success ?
    def generateReleaseNote_HTML
      rSuccess = true

      puts "==== Generating release note in HTML format ..."
      lLastChangesLines = []
      File.open("#{@RootDir}/ChangeLog", 'r') do |iFile|
        lInLastVersionSection = false
        iFile.readlines.each do |iLine|
          if (iLine.match(/^== /) != nil)
            if (lInLastVersionSection)
              # Nothing else to parse
              break
            else
              # We are beginning the section corresponding to the last version
              lInLastVersionSection = true
            end
          elsif (lInLastVersionSection)
            # This line belongs to the last version section
            lLastChangesLines << iLine.
              gsub(/\n/,"<br/>\n").
              gsub(/^=== (.*)$/, '<h3>\1</h3>').
              gsub(/^\* (.*)$/, '<li>\1</li>').
              gsub(/Bug correction/, '<span class="Bug">Bug correction</span>')
          end
        end
      end
      File.open("#{@DocDir}/ReleaseNote.html", 'w') do |oFile|
        oFile << "
<html>
  <head>
    <link rel=\"shortcut icon\" href=\"#{@ReleaseInfo.ProjectInfo[:FaviconURL]}%>\" />
    <style type=\"text/css\">
      body {
        background: #fdfdfd;
        font: 14px \"Helvetica Neue\", Helvetica, Tahoma, sans-serif;
      }
      img {
        border: none;
      }
      h1 {
        text-shadow: rgba(135,145,135,0.65) 2px 2px 3px;
        color: #6C8C22;
      }
      h2 {
        padding: 2px 8px;
        background: #ccc;
        color: #666;
        -moz-border-radius-topleft: 4px;
        -moz-border-radius-topright: 4px;
        -webkit-border-top-left-radius: 4px;
        -webkit-border-top-right-radius: 4px;
        border-bottom: 1px solid #aaa;
      }
      h3 {
        padding: 2px 32px;
        background: #ddd;
        color: #666;
        -moz-border-radius-topleft: 4px;
        -moz-border-radius-topright: 4px;
        -webkit-border-top-left-radius: 4px;
        -webkit-border-top-right-radius: 4px;
        border-bottom: 1px solid #aaa;
      }
      .Bug {
        color: red;
        font-weight: bold;
      }
      .Important {
        color: #633;
        font-weight: bold;
      }
      ul {
        line-height: 160%;
      }
      li {
        padding-left: 20px;
      }
    </style>
  </head>
  <body>
    <a href=\"#{@ReleaseInfo.ProjectInfo[:WebPageURL]}\"><img src=\"#{@ReleaseInfo.ProjectInfo[:ImageURL]}\" align=\"right\" width=\"100px\"/></a>
    <h1>Release Note for #{@ReleaseInfo.ProjectInfo[:Name]} - v. #{@ReleaseVersion}</h1>
    <h2>Development status: <span class=\"Important\">#{@ReleaseInfo.ProjectInfo[:DevStatus]}</span></h2>
    <h2>What's new in this release</h2>
#{@ReleaseComment.gsub(/\n/,"<br/>\n")}
    <h2>Detailed changes with previous version</h2>
#{lLastChangesLines.join}
    <h2>Useful links</h2>
    <ul>
      <li><a href=\"#{@ReleaseInfo.ProjectInfo[:WebPageURL]}\">Project web site</a></li>
      <li><a href=\"https://sourceforge.net/projects/#{@ReleaseInfo.SFInfo[:ProjectUnixName]}/files/#{@ReleaseVersion}/#{@GemName}/download\">Download</a></li>
      <li>Author: <a href=\"#{@ReleaseInfo.AuthorInfo[:WebPageURL]}\">#{@ReleaseInfo.AuthorInfo[:Name]}</a> (<a href=\"mailto://#{@ReleaseInfo.AuthorInfo[:EMail]}\">Contact</a>)</li>
      <li><a href=\"#{@ReleaseInfo.ProjectInfo[:WebPageURL]}rdoc/#{@ReleaseVersion}\">Browse RDoc</a></li>
      <li><a href=\"#{@ReleaseInfo.ProjectInfo[:SVNBrowseURL]}\">Browse SVN</a></li>
      <li><a href=\"#{@ReleaseInfo.ProjectInfo[:SVNBrowseURL]}ChangeLog?view=markup\">View complete ChangeLog</a></li>
      <li><a href=\"#{@ReleaseInfo.ProjectInfo[:SVNBrowseURL]}README?view=markup\">View README file</a></li>
    </ul>
  </body>
</html>
"
      end

      return rSuccess
    end

    # Generate a release note file to attach to this release
    #
    # Return:
    # * _Boolean_: Success ?
    def generateReleaseNote_TXT
      rSuccess = true

      puts "==== Generating release note in TXT format ..."
      lLastChangesLines = []
      File.open("#{@RootDir}/ChangeLog", 'r') do |iFile|
        lInLastVersionSection = false
        iFile.readlines.each do |iLine|
          if (iLine.match(/^== /) != nil)
            if (lInLastVersionSection)
              # Nothing else to parse
              break
            else
              # We are beginning the section corresponding to the last version
              lInLastVersionSection = true
            end
          elsif (lInLastVersionSection)
            # This line belongs to the last version section
            lLastChangesLines << iLine
          end
        end
      end
      File.open("#{@DocDir}/ReleaseNote.txt", 'w') do |oFile|
        oFile << "
= Release Note for #{@ReleaseInfo.ProjectInfo[:Name]} - v. #{@ReleaseVersion}

== Development status: #{@ReleaseInfo.ProjectInfo[:DevStatus]}

== What's new in this release

#{@ReleaseComment}

== Detailed changes with previous version

#{lLastChangesLines.join}

==  Useful links

* Project web site: #{@ReleaseInfo.ProjectInfo[:WebPageURL]}
* Download: https://sourceforge.net/projects/#{@ReleaseInfo.ProjectInfo[:ProjectUnixName]}/files/#{@ReleaseVersion}/#{@GemName}/download
* Author: #{@ReleaseInfo.AuthorInfo[:Name]} (#{@ReleaseInfo.AuthorInfo[:WebPageURL]}) (Mail: #{@ReleaseInfo.AuthorInfo[:EMail]})
* Browse RDoc: #{@ReleaseInfo.ProjectInfo[:WebPageURL]}rdoc/#{@ReleaseVersion}
* Browse SVN: #{@ReleaseInfo.ProjectInfo[:SVNBrowseURL]}
* View complete ChangeLog: #{@ReleaseInfo.ProjectInfo[:SVNBrowseURL]}ChangeLog?view=markup
* View README file: #{@ReleaseInfo.ProjectInfo[:SVNBrowseURL]}README?view=markup
"
      end

      return rSuccess
    end

  end

end
