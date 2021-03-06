# coding: utf-8

# Release a distribution of a Ruby program.
# This produces an installable executable that will install a set of files and directories:
# * A binary, including some core Ruby and program files (eventually the whole Ruby distribution if needed - that is if the program is meant to be run on platforms not providing Ruby)
# * A list of files/directories

require 'fileutils'

module RubyPackager

  # Copy a list of files patterns to the release directory
  #
  # Parameters::
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
            log_debug "Create directory #{lRelativeName}"
          else
            log_debug "Copy file #{lRelativeName}"
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
    # Parameters::
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
    # * *iGenerateRDoc* (_Boolean_): Do we generate RDoc ?
    # * *iInstallers* (<em>list<String></em>): The list of installers to generate
    # * *iDistributors* (<em>list<String></em>): The list of distributors to ship installers to
    def initialize(iPluginsManager, iReleaseInfo, iRootDir, iReleaseBaseDir, iPlatformReleaseInfo, iReleaseVersion, iReleaseTags, iReleaseComment, iIncludeRuby, iIncludeTest, iGenerateRDoc, iInstallers, iDistributors)
      @PluginsManager, @ReleaseInfo, @RootDir, @ReleaseBaseDir, @PlatformReleaseInfo, @ReleaseVersion, @ReleaseTags, @ReleaseComment, @IncludeRuby, @IncludeTest, @GenerateRDoc, @Installers, @Distributors = iPluginsManager, iReleaseInfo, iRootDir, iReleaseBaseDir, iPlatformReleaseInfo, iReleaseVersion, iReleaseTags, iReleaseComment, iIncludeRuby, iIncludeTest, iGenerateRDoc, iInstallers, iDistributors
      @GemName = "#{@ReleaseInfo.gem_info[:gem_name]}-#{@ReleaseVersion}.gem"
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
      lBaseReleaseDir = "#{@ReleaseBaseDir}/#{RUBY_PLATFORM}/#{@ReleaseVersion}/#{lStrOptions}/#{Time.now.strftime('%Y_%m_%d_%H_%M_%S')}"
      log_debug "Release to be performed in #{lBaseReleaseDir}"
      @InstallerDir = "#{lBaseReleaseDir}/Installer"
      @DocDir = "#{lBaseReleaseDir}/Documentation"
      @ReleaseDir = "#{lBaseReleaseDir}/Release"
      require 'fileutils'
      FileUtils.mkdir_p(@ReleaseDir)
      FileUtils.mkdir_p(@InstallerDir)
      FileUtils.mkdir_p(@DocDir)
    end

    # Release
    #
    # Return::
    # * _Boolean_: Success ?
    def execute
      rSuccess = true

      # First check that every tool we will need is present
      # TODO: Use RDI to install missing ones
      logOp('Check installed tools') do
        # Check that the tools we need to release are indeed here
        if ((@ReleaseInfo.respond_to?(:check_ready_for_release)) and
            (!@ReleaseInfo.check_ready_for_release(@RootDir)))
          rSuccess = false
        end
        if (!@ReleaseInfo.executables_info.empty?)
          # Check first if there will be a need for binary compilation
          lBinaryCompilation = false
          @ReleaseInfo.executables_info.each do |iExecutableInfo|
            if (iExecutableInfo[:exe_name] != nil)
              lBinaryCompilation = true
              break
            end
          end
          # Check tools for platform dependent considerations
          if (!@PlatformReleaseInfo.check_exe_tools(@RootDir, @IncludeRuby, lBinaryCompilation))
            rSuccess = false
          end
        end
        @Installers.each do |iInstallerName|
          @PluginsManager.access_plugin('Installers', iInstallerName) do |ioPlugin|
            if ((ioPlugin.respond_to?(:check_tools)) and
                (!ioPlugin.check_tools))
              rSuccess = false
            end
          end
        end
        @Distributors.each do |iDistributorName|
          @PluginsManager.access_plugin('Distributors', iDistributorName) do |ioPlugin|
            if ((ioPlugin.respond_to?(:check_tools)) and
                (!ioPlugin.check_tools))
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
          if (@GenerateRDoc)
            rSuccess = generateRDoc
          end
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
                @Installers.each do |iInstallerName|
                  logOp("Create installer #{iInstallerName}") do
                    @PluginsManager.access_plugin('Installers', iInstallerName) do |ioPlugin|
                      lFileName = ioPlugin.create_installer(@RootDir, @ReleaseDir, @InstallerDir, @ReleaseVersion, @ReleaseInfo, @IncludeTest)
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
                      @PluginsManager.access_plugin('Distributors', iDistributorName) do |ioPlugin|
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
    # Parameters::
    # * *iOperationName* (_String_): Operation name
    # * *CodeBlock*: Code to call in this operation
    def logOp(iOperationName)
      log_debug "===== #{iOperationName} ..."
      yield
      log_debug "===== ... #{iOperationName}"
    end

    # Release files in a directory, and create the executable if needed
    #
    # Return::
    # * _Boolean_: Success ?
    def releaseFiles
      rSuccess = true

      logOp('Copy core files') do
        RubyPackager::copyFiles(@RootDir, @ReleaseDir, @ReleaseInfo.core_files)
        # Create the ReleaseVersion file
        lStrTags = nil
        if (@ReleaseTags.empty?)
          lStrTags = ':tags => []'
        else
          lStrTags = ":tags => [ '#{@ReleaseTags.join('\', \'')}' ]"
        end
        File.open("#{@ReleaseDir}/ReleaseInfo", 'w') do |oFile|
          oFile << "
# This file has been generated by RubyPackager during a delivery.
# More info about RubyPackager: http://rubypackager.sourceforge.net
{
  :version => '#{@ReleaseVersion}',
  #{lStrTags},
  :dev_status => '#{@ReleaseInfo.project_info[:dev_status]}'
}
"
        end
      end
      @ReleaseInfo.executables_info.each do |iExecutableInfo|
        if (iExecutableInfo[:exe_name] != nil)
          logOp("Create binary #{iExecutableInfo[:exe_name]}") do
            # TODO (crate): When crate will work correctly under Windows, use it here to pack everything
            # For now the executable creation is platform dependent
            rSuccess = @PlatformReleaseInfo.create_binary(@RootDir, @ReleaseDir, @IncludeRuby, iExecutableInfo)
          end
        end
      end
      if (rSuccess)
        logOp('Copy additional files') do
          RubyPackager::copyFiles(@RootDir, @ReleaseDir, @ReleaseInfo.additional_files)
        end
        if (@IncludeTest)
          logOp('Copy test files') do
            RubyPackager::copyFiles(@RootDir, @ReleaseDir, @ReleaseInfo.test_files)
          end
        end
      end

      return rSuccess
    end

    # Generate rdoc
    #
    # Return::
    # * _Boolean_: Success ?
    def generateRDoc
      rSuccess = true

      logOp('Generating RDoc') do
        # This was used by modifications to RDoc for Muriel's template.
        # Consider it as obsolete now.
        # TODO: Remove/Adapt when Muriel's template is a well written RDoc gem.
#        $project_info = {
#          :Name => @ReleaseInfo.project_info[:name],
#          :version => @ReleaseVersion,
#          :tags => @ReleaseTags,
#          :Date => Time.now,
#          :dev_status => @ReleaseInfo.project_info[:dev_status],
#          :Author => @ReleaseInfo.author_info[:name],
#          :AuthorMail => @ReleaseInfo.author_info[:email],
#          :AuthorURL => @ReleaseInfo.author_info[:web_page_url],
#          :HomepageURL => @ReleaseInfo.project_info[:web_page_url],
#          :image_url => @ReleaseInfo.project_info[:image_url],
#          # TODO: Do not hardcode SF anymore
#          :DownloadURL => "https://sourceforge.net/projects/#{@ReleaseInfo.sf_info[:project_unix_name]}/files/#{@ReleaseVersion}/#{@GemName}/download",
#          :browse_source_url => @ReleaseInfo.project_info[:browse_source_url],
#          :favicon_url => @ReleaseInfo.project_info[:favicon_url],
#          # For the documentation, the Root dir is the Release dir as files have been copied there and the rdoc will be generated from there.
#          :RootDir => @ReleaseDir
#        }
        # Create the created.rid file as otherwise rdoc will not finish
        FileUtils::mkdir_p("#{@DocDir}/rdoc")
        File.open("#{@DocDir}/rdoc/created.rid", 'w') do |oFile|
        end
        gem 'rdoc'
        require 'rdoc/rdoc'
        lRDocOptions = [
          '--line-numbers',
          '--tab-width=2',
          "--title=#{@ReleaseInfo.project_info[:name].gsub(/'/,'\\\\\'')} v#{@ReleaseVersion}",
          '--hyperlink-all',
          '--charset=utf-8',
          '--exclude=.svn',
          '--exclude=.git',
          '--exclude=nbproject',
          '--exclude=Done.txt',
          '--exclude=Releases',
          '--force-update',
          "--output=#{@DocDir}/rdoc"
        ]
        # Bug (RDoc): Sometimes it does not change current directory correctly (not deterministic)
        change_dir(@ReleaseDir) do
          # First try with Muriel's template
          begin
            RDoc::RDoc.new.document( lRDocOptions + [ '--fmt=muriel' ] )
          rescue Exception
            log_warn "Exception while generating using Muriel's templates: #{$!}: #{$!.backtrace.join("\n")}"
            # Then try with default template
            RDoc::RDoc.new.document( lRDocOptions )
          end
        end
      end

      return rSuccess
    end

    # Generate a release note file to attach to this release
    #
    # Return::
    # * _Boolean_: Success ?
    def generateReleaseNote_HTML
      rSuccess = true

      logOp('Generating release note in HTML format') do
        lLastChangesLines = []
        getLastChangeLog.each do |iLine|
          lLastChangesLines << iLine.
            gsub(/\n/,"<br/>\n").
            gsub(/^=== (.*)$/, '<h3>\1</h3>').
            gsub(/^\* (.*)$/, '<li>\1</li>').
            gsub(/Bug correction/, '<span class="Bug">Bug correction</span>')
        end
        lStrWhatsNew = ''
        if (@ReleaseComment != nil)
          lStrWhatsNew = "
<h2>What's new in this release</h2>
#{@ReleaseComment.gsub(/\n/,"<br/>\n")}
          "
        end
        File.open("#{@DocDir}/ReleaseNote.html", 'w') do |oFile|
          oFile << "
<html>
  <head>
    <link rel=\"shortcut icon\" href=\"#{@ReleaseInfo.project_info[:favicon_url]}%>\" />
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
    <a href=\"#{@ReleaseInfo.project_info[:web_page_url]}\"><img src=\"#{@ReleaseInfo.project_info[:image_url]}\" align=\"right\" width=\"100px\"/></a>
    <h1>Release Note for #{@ReleaseInfo.project_info[:name]} - v. #{@ReleaseVersion}</h1>
    <h2>Development status: <span class=\"Important\">#{@ReleaseInfo.project_info[:dev_status]}</span></h2>
#{lStrWhatsNew}
    <h2>Detailed changes with previous version</h2>
#{lLastChangesLines.join}
    <h2>Useful links</h2>
    <ul>
      <li><a href=\"#{@ReleaseInfo.project_info[:web_page_url]}\">Project web site</a></li>
      <li><a href=\"https://sourceforge.net/projects/#{@ReleaseInfo.sf_info[:project_unix_name]}/files/#{@ReleaseVersion}/#{@GemName}/download\">Download</a></li>
      <li>Author: <a href=\"#{@ReleaseInfo.author_info[:web_page_url]}\">#{@ReleaseInfo.author_info[:name]}</a> (<a href=\"mailto://#{@ReleaseInfo.author_info[:email]}\">Contact</a>)</li>
      <li><a href=\"#{@ReleaseInfo.project_info[:web_page_url]}rdoc/#{@ReleaseVersion}\">Browse RDoc</a></li>
      <li><a href=\"#{@ReleaseInfo.project_info[:browse_source_url]}\">Browse source</a></li>
      <li><a href=\"#{@ReleaseInfo.project_info[:browse_source_url]}ChangeLog?view=markup\">View complete ChangeLog</a></li>
      <li><a href=\"#{@ReleaseInfo.project_info[:browse_source_url]}README?view=markup\">View README file</a></li>
    </ul>
  </body>
</html>
"
        end
      end

      return rSuccess
    end

    # Generate a release note file to attach to this release
    #
    # Return::
    # * _Boolean_: Success ?
    def generateReleaseNote_TXT
      rSuccess = true

      logOp('Generating release note in TXT format') do
        lStrWhatsNew = ''
        if (@ReleaseComment != nil)
          lStrWhatsNew = "
== What's new in this release

#{@ReleaseComment}

"
        end
        File.open("#{@DocDir}/ReleaseNote.txt", 'w') do |oFile|
          oFile << "
= Release Note for #{@ReleaseInfo.project_info[:name]} - v. #{@ReleaseVersion}

== Development status: #{@ReleaseInfo.project_info[:dev_status]}

#{lStrWhatsNew}
== Detailed changes with previous version

#{getLastChangeLog.join}

==  Useful links

* Project web site: #{@ReleaseInfo.project_info[:web_page_url]}
* Download: https://sourceforge.net/projects/#{@ReleaseInfo.project_info[:project_unix_name]}/files/#{@ReleaseVersion}/#{@GemName}/download
* Author: #{@ReleaseInfo.author_info[:name]} (#{@ReleaseInfo.author_info[:web_page_url]}) (Mail: #{@ReleaseInfo.author_info[:email]})
* Browse RDoc: #{@ReleaseInfo.project_info[:web_page_url]}rdoc/#{@ReleaseVersion}
* Browse source: #{@ReleaseInfo.project_info[:browse_source_url]}
* View complete ChangeLog: #{@ReleaseInfo.project_info[:browse_source_url]}ChangeLog?view=markup
* View README file: #{@ReleaseInfo.project_info[:browse_source_url]}README?view=markup
"
        end
      end

      return rSuccess
    end

    # Get the last change log
    #
    # Return::
    # * <em>list<String></em>: The change log lines
    def getLastChangeLog
      rLastChangesLines = []

      lChangeLogFileName = "#{@RootDir}/ChangeLog"
      if (File.exists?(lChangeLogFileName))
        File.open(lChangeLogFileName, 'r') do |iFile|
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
              rLastChangesLines << iLine
            end
          end
        end
      end

      return rLastChangesLines
    end

  end

end
