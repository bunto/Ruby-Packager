module RubyPackager

  module Test

    module Cygwin

      class Executable < ::Test::Unit::TestCase

        include RubyPackager::Test::Common

        # Test the basic usage generating an executable
        def testBasicBinary
          execTest('Applications/Basic', [], 'ReleaseInfo_Exe.rb') do |iReleaseDir, iReleaseInfo|
            checkReleaseInfo(iReleaseDir, iReleaseInfo)
            checkReleaseNotes(iReleaseDir, iReleaseInfo)
            lExeFileName = "#{iReleaseDir}/Release/ExeName"
            assert(File.exists?(lExeFileName))
            # Unless the Executable file can contain other rb files (please Crate come faster !), files are still present.
            assert(File.exists?("#{iReleaseDir}/Release/Main.rb"))
            # Test it in Ruby's environment
            assert_equal("Ruby found on current platform. Use it directly.
Hello World\n", runExe(lExeFileName))
            # TODO: Test it without Ruby's environment
          end
        end

        # Test the basic usage generating an executable in a terminal
        def testBasicBinaryInTerminal
          execTest('Applications/Basic', [], 'ReleaseInfo_ExeTerm.rb') do |iReleaseDir, iReleaseInfo|
            checkReleaseInfo(iReleaseDir, iReleaseInfo)
            checkReleaseNotes(iReleaseDir, iReleaseInfo)
            lExeFileName = "#{iReleaseDir}/Release/ExeName"
            assert(File.exists?(lExeFileName))
            # Unless the Executable file can contain other rb files (please Crate come faster !), files are still present.
            assert(File.exists?("#{iReleaseDir}/Release/Main.rb"))
            # Test it in Ruby's environment
            assert_equal("Ruby found on current platform. Use it directly.
Hello World\n", runExe(lExeFileName))
            # TODO: Test it without Ruby's environment
          end
        end

        # Test the basic usage generating an executable, including Ruby
        def testBasicBinaryWithRuby
          lReleaseBaseDir = Regexp.escape("Releases/#{RUBY_PLATFORM}/UnnamedVersion/IncludeRuby/") + '\\d\\d\\d\\d_\\d\\d_\\d\\d_\\d\\d_\\d\\d_\\d\\d'
          execTest('Applications/Basic', [ '-r' ], 'ReleaseInfo_Exe.rb', :ExpectCalls => [
            [ 'system',
              {
                :Dir => /^.*\/#{lReleaseBaseDir}\/Release\/Launch\/cygwin\/bin$/,
                :Cmd => /^allinoneruby ruby\-\d\.\d\.\d\.bin$/
              },
              { :Execute => $RBPTest_ExternalTools ? true : Proc.new { true } }
            ]
          ]) do |iReleaseDir, iReleaseInfo|
            checkReleaseInfo(iReleaseDir, iReleaseInfo)
            checkReleaseNotes(iReleaseDir, iReleaseInfo)
            lExeFileName = "#{iReleaseDir}/Release/ExeName"
            assert(File.exists?(lExeFileName))
            # Unless the Executable file can contain other rb files (please Crate come faster !), files are still present.
            assert(File.exists?("#{iReleaseDir}/Release/Main.rb"))
            # Test it in Ruby's environment
            assert_equal("Ruby found on current platform. Use it directly.
Hello World\n", runExe(lExeFileName))
            # TODO: Test it without Ruby's environment
          end
        end

        # Test the basic usage generating an executable, including Ruby launched from a terminal
        def testBasicBinaryWithRubyInTerminal
          lReleaseBaseDir = Regexp.escape("Releases/#{RUBY_PLATFORM}/UnnamedVersion/IncludeRuby/") + '\\d\\d\\d\\d_\\d\\d_\\d\\d_\\d\\d_\\d\\d_\\d\\d'
          execTest('Applications/Basic', [ '-r' ], 'ReleaseInfo_ExeTerm.rb', :ExpectCalls => [
            [ 'system',
              {
                :Dir => /^.*\/#{lReleaseBaseDir}\/Release\/Launch\/cygwin\/bin$/,
                :Cmd => /^allinoneruby ruby\-\d\.\d\.\d\.bin$/
              },
              { :Execute => $RBPTest_ExternalTools ? true : Proc.new { true } }
            ]
          ]) do |iReleaseDir, iReleaseInfo|
            checkReleaseInfo(iReleaseDir, iReleaseInfo)
            checkReleaseNotes(iReleaseDir, iReleaseInfo)
            lExeFileName = "#{iReleaseDir}/Release/ExeName"
            assert(File.exists?(lExeFileName))
            # Unless the Executable file can contain other rb files (please Crate come faster !), files are still present.
            assert(File.exists?("#{iReleaseDir}/Release/Main.rb"))
            # Test it in Ruby's environment
            assert_equal("Ruby found on current platform. Use it directly.
Hello World\n", runExe(lExeFileName))
            # TODO: Test it without Ruby's environment
          end
        end

      end

    end

  end

end
