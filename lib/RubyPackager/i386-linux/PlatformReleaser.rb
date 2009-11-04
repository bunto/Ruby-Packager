#--
# Copyright (c) 2009 Muriel Salvan (murielsalvan@users.sourceforge.net)
# Licensed under the terms specified in LICENSE file. No warranty is provided.
#++

# This file prepares a win32 distribution

# Require needed to generate the temporary ruby file that produces the executable
require 'tmpdir'

module RubyPackager

  class PlatformReleaser

    PLATFORM_DIR = File.dirname(__FILE__)

    # Check if the tools we will use to generate an executable are present
    #
    # Parameters:
    # * *iRootDir* (_String_): Root directory
    # * *iIncludeRuby* (_Boolean_): Do we include Ruby in the release ?
    # Return:
    # * _Boolean_: Are tools correctly useable ?
    def checkExeTools(iRootDir, iIncludeRuby)
      rSuccess = true

      if (iIncludeRuby)
        # We need allinoneruby
        if (Gem.find_files('allinoneruby').empty?)
          logErr "Need to have allinoneruby gem to release including Ruby.\nPlease install allinoneruby gem (gem install allinoneruby)."
          rSuccess = false
        end
      end

      return rSuccess
    end

    # Create the binary.
    # This is called when the core library has been copied in the release directory.
    #
    # Parameters:
    # * *iRootDir* (_String_): Root directory
    # * *iReleaseDir* (_String_): Release directory
    # * *iIncludeRuby* (_Boolean_): Do we include Ruby in the release ?
    # * *iReleaseInfo* (_ReleaseInfo_): The release information
    # Return:
    # * _Boolean_: Success ?
    def createBinary(iRootDir, iReleaseDir, iIncludeRuby, iReleaseInfo)
      rSuccess = true

      lBinSubDir = "Launch/#{RUBY_PLATFORM}/bin"
      lRubyBaseBinName = nil
      lRubyLaunchCmd = nil
      lRubyBaseBinName = 'ruby'
      lRubyLaunchCmd = 'ruby'
      lBinName = "#{lRubyBaseBinName}-#{RUBY_VERSION}.bin"
      if (iIncludeRuby)
        # First create the binary containing all ruby
        lBinDir = "#{iReleaseDir}/#{lBinSubDir}"
        FileUtils::mkdir_p(lBinDir)
        lOldDir = Dir.getwd
        Dir.chdir(lBinDir)
        lCmd = "allinoneruby #{lBinName}"
        rSuccess = system(lCmd)
        if (!rSuccess)
          logErr "Error while executing \"#{lCmd}\""
        end
        Dir.chdir(lOldDir)
      end
      if (rSuccess)
        # Then create the real executable
        # Generate the Shell file that launches everything for Linux
        File.open("#{iReleaseDir}/#{iReleaseInfo.ExecutableInfo[:ExeName]}", 'w') do |oFile|
          oFile << "
\#!/bin/sh
\#--
\# Copyright (c) 2009 Muriel Salvan (murielsalvan@users.sourceforge.net)
\# Licensed under the terms specified in LICENSE file. No warranty is provided.
\#++

\# This file is generated by RubyPackager for Linux.

\# This file has to launch the correct binary. There can be several binaries dependending on the configuration.
\# This is the file that will be created as the executable to launch.

\# Test Ruby's existence
which ruby >/dev/null 2>/dev/null
if [ $? == 1 ]
then
  echo 'Ruby not found on current platform. Use embedded one.'
  if [ ! -d tempruby ]
  then
    echo 'Extracting Ruby distribution...'
    mkdir tempruby
    cd tempruby
    ../#{lBinSubDir}/#{lBinName} --eee-justextract
    cd ..
  fi
  \# Set the environment correctly to execute Ruby from the extracted dir
  export LD_LIBRARY_PATH=`pwd`/tempruby/bin:`pwd`/tempruby/lib:`pwd`/tempruby/lib/lib1:`pwd`/tempruby/lib/lib2:`pwd`/tempruby/lib/lib3:`pwd`/tempruby/lib/lib4:${LD_LIRARY_PATH}
  export RUBYOPT=
  ./tempruby/bin/ruby -w #{iReleaseInfo.ExecutableInfo[:StartupRBFile]}
else
  echo 'Ruby found on current platform. Use it directly.'
  ruby -w #{iReleaseInfo.ExecutableInfo[:StartupRBFile]}
fi
"
        end
        File.chmod(0755, "#{iReleaseDir}/#{iReleaseInfo.ExecutableInfo[:ExeName]}")
      end

      return rSuccess
    end

  end

end
